import Foundation
import Combine

/// (venueId, qrToken) pair captured from either the in-app scanner or an
/// incoming Universal Link. Anywhere the check-in flow needs both gates
/// (which venue, which secret) this is what's threaded through.
struct ScannedVenueQR: Equatable {
    let venueId: VenueId
    let qrToken: String
}

/// Pure parsers for the venue-QR payload. The printed QRs always encode a
/// Universal Link URL, but we accept a custom-scheme form too so we have
/// an escape hatch if Apple's AASA cache misbehaves at a venue.
///
/// Accepted shapes:
///   1. `https://<host>/v/<venueId>?q=<token>`  ← Universal Link (primary)
///   2. `http://<host>/v/<venueId>?q=<token>`   ← same, dev-friendly
///   3. `mrp:venue/<venueId>?q=<token>`         ← custom scheme fallback
///
/// The host isn't validated here — it's checked at the entitlement layer
/// (associated-domains) when iOS resolves the Universal Link. By the time
/// the URL lands in `parseVenueQR`, the system has already confirmed it
/// belongs to an entitled host.
enum DeepLink {
    static func parseVenueQR(from raw: String) -> ScannedVenueQR? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        switch url.scheme?.lowercased() {
        case "https", "http":
            return parseHTTP(url)
        case "mrp":
            return parseCustomScheme(url)
        default:
            return nil
        }
    }

    private static func parseHTTP(_ url: URL) -> ScannedVenueQR? {
        // Path components for `/v/<venueId>` come through as ["/", "v", "<id>"].
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "v" else { return nil }
        guard let venue = VenueId(rawValue: parts[2]) else { return nil }
        guard let token = queryValue(in: url, key: "q"), !token.isEmpty else { return nil }
        return ScannedVenueQR(venueId: venue, qrToken: token)
    }

    private static func parseCustomScheme(_ url: URL) -> ScannedVenueQR? {
        // `mrp:venue/<id>?q=<token>` — URLComponents parses the part after
        // `mrp:` into `path = "venue/<id>"`. Strip the leading "venue/"
        // segment.
        let path = url.path
        let prefix = "venue/"
        guard path.hasPrefix(prefix) else { return nil }
        let venueRaw = String(path.dropFirst(prefix.count))
        guard let venue = VenueId(rawValue: venueRaw) else { return nil }
        guard let token = queryValue(in: url, key: "q"), !token.isEmpty else { return nil }
        return ScannedVenueQR(venueId: venue, qrToken: token)
    }

    private static func queryValue(in url: URL, key: String) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == key })?.value
    }
}

/// Holds the most recent venue-QR scanned via Universal Links. The in-app
/// scanner doesn't go through here — the views that present the scanner
/// handle its result directly. This router is for system-camera scans that
/// hand the URL off to `onOpenURL` while the app is cold-launched or
/// already running.
///
/// `pendingScan` is consumed by whichever screen is currently in front:
///   - RegisterView reads it to pre-fill venue + token on first launch.
///   - PassportView reads it to trigger the inline check-in for a
///     returning customer.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingScan: ScannedVenueQR?

    private init() {}

    func ingest(url: URL) {
        if let scan = DeepLink.parseVenueQR(from: url.absoluteString) {
            pendingScan = scan
        }
    }

    func consume() -> ScannedVenueQR? {
        let value = pendingScan
        pendingScan = nil
        return value
    }
}
