import Foundation
import Network
import Combine

/// One client-confirmed action waiting to land on the server. Persisted in
/// UserDefaults so a force-quit or crash doesn't lose a confirmed tap.
///
/// `kind` distinguishes the two flavors:
///   - `.checkin` — initial stamp; requires latitude/longitude (the client
///     has pre-verified the geofence and only an in-range tap will enqueue).
///   - `.checkout` — "I'm leaving" tap. No coords required.
///   - `.checkoutEdit` — adjust a previously-set checkout time, e.g. to fix
///     a forgotten one or a stale auto-estimate. `observedAt` is the new
///     value to write.
struct PendingCheckin: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case checkin
        case checkout
        case checkoutEdit
    }

    let id: UUID
    let kind: Kind
    let token: String
    let venueId: VenueId
    let latitude: Double?
    let longitude: Double?
    /// `.checkin`: when the user pressed Check-in (we surface this as the
    /// stamp's `checkedInAt` in the optimistic merge so stop numbering
    /// matches what the server will eventually persist).
    /// `.checkout` / `.checkoutEdit`: the timestamp to record / set.
    let observedAt: Date

    /// Backwards-compat decoder: rows persisted before the `kind` field
    /// existed were always check-ins, so default to that and treat
    /// latitude/longitude as required for older rows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .checkin
        token = try c.decode(String.self, forKey: .token)
        venueId = try c.decode(VenueId.self, forKey: .venueId)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
    }

    init(id: UUID, kind: Kind, token: String, venueId: VenueId, latitude: Double?, longitude: Double?, observedAt: Date) {
        self.id = id
        self.kind = kind
        self.token = token
        self.venueId = venueId
        self.latitude = latitude
        self.longitude = longitude
        self.observedAt = observedAt
    }
}

/// Pending-stamp queue. Single-instance because we want one network-flush
/// loop across the app, not one per view. Mark `@MainActor` so callers can
/// read `pending` from SwiftUI without dancing around isolation.
///
/// Lifecycle:
///   - `enqueue` is called from PassportView's inline check-in flow the
///     moment the local geofence check passes — independent of whether the
///     network request has even been attempted yet, so the stamp is durable
///     through any failure mode.
///   - `flush` posts each pending item to /passport/checkin, dropping on
///     success (200) or terminal failures (409 duplicate, 4xx that won't
///     fix itself). Network/5xx errors leave the item in place for the next
///     attempt.
///   - We retry automatically on app foreground and when NWPathMonitor sees
///     the network come back; callers can also call `flush()` directly.
@MainActor
final class CheckinQueue: ObservableObject {
    static let shared = CheckinQueue()

    @Published private(set) var pending: [PendingCheckin] = []
    @Published private(set) var isFlushing = false

    private static let storageKey = "checkinQueue.v1"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "checkinQueue.monitor")
    private var hasNetwork: Bool = true

    private init() {
        pending = Self.load()
        startNetworkMonitor()
    }

    /// Add a pending action. Returns true if it was newly added; false if
    /// an equivalent action (same token + venueId + kind) was already
    /// queued — that way double-taps don't enqueue twice. `.checkoutEdit`
    /// always replaces a prior edit for the same row so the latest user-
    /// chosen value wins.
    @discardableResult
    func enqueue(_ item: PendingCheckin) -> Bool {
        if item.kind == .checkoutEdit {
            pending.removeAll { $0.token == item.token && $0.venueId == item.venueId && $0.kind == .checkoutEdit }
        } else if pending.contains(where: { $0.token == item.token && $0.venueId == item.venueId && $0.kind == item.kind }) {
            return false
        }
        pending.append(item)
        persist()
        Task { await flush() }
        return true
    }

    @discardableResult
    func enqueueCheckout(token: String, venueId: VenueId, at: Date = Date()) -> Bool {
        enqueue(PendingCheckin(
            id: UUID(),
            kind: .checkout,
            token: token,
            venueId: venueId,
            latitude: nil,
            longitude: nil,
            observedAt: at
        ))
    }

    @discardableResult
    func enqueueCheckoutEdit(token: String, venueId: VenueId, newCheckedOutAt: Date) -> Bool {
        enqueue(PendingCheckin(
            id: UUID(),
            kind: .checkoutEdit,
            token: token,
            venueId: venueId,
            latitude: nil,
            longitude: nil,
            observedAt: newCheckedOutAt
        ))
    }

    /// Drop everything for a given token (e.g. user signed out via reset).
    func clear(forToken token: String) {
        pending.removeAll { $0.token == token }
        persist()
    }

    /// Attempt to drain the queue. Safe to call repeatedly — guarded so we
    /// don't run two flushes concurrently and accidentally fire each pending
    /// request twice.
    func flush() async {
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        for item in pending {
            do {
                switch item.kind {
                case .checkin:
                    guard let lat = item.latitude, let lon = item.longitude else {
                        // Corrupt row — drop to avoid blocking the queue.
                        remove(item.id)
                        continue
                    }
                    _ = try await APIClient.checkin(CheckinRequest(
                        passportToken: item.token,
                        venueId: item.venueId,
                        latitude: lat,
                        longitude: lon
                    ))
                case .checkout:
                    _ = try await APIClient.checkout(token: item.token, venueId: item.venueId)
                case .checkoutEdit:
                    _ = try await APIClient.editCheckout(token: item.token, venueId: item.venueId, checkedOutAt: item.observedAt)
                }
                remove(item.id)
            } catch APIError.server(let msg) {
                // Server reachable but rejected — most common cause is the
                // duplicate-stamp 409 (queue retried after the original
                // succeeded, or two devices). Either way the work the queue
                // represents is reflected on the server, so dropping is
                // correct.
                let lower = msg.lowercased()
                if lower.contains("already stamped")
                    || lower.contains("already") {
                    remove(item.id)
                } else {
                    // Unrecoverable validation error (e.g. unknown venue,
                    // bad range). Drop to avoid infinite retry; the
                    // misbehaving call would otherwise block every other
                    // queued item.
                    remove(item.id)
                }
            } catch {
                // Network/transport failure — leave in place. We'll retry
                // on the next reachability flip or app foreground.
                break
            }
        }
    }

    private func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(pending)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Encoding a Codable array can't realistically fail; swallow
            // rather than crash a customer's check-in on a cold edge case.
        }
    }

    private static func load() -> [PendingCheckin] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingCheckin].self, from: data)) ?? []
    }

    /// React to the device coming back online — auto-flush so the user
    /// doesn't have to open the app or tap retry once wifi recovers.
    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            Task { @MainActor in
                let cameOnline = online && !self.hasNetwork
                self.hasNetwork = online
                if cameOnline { await self.flush() }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
