import Foundation

/// Tiny wrapper around UserDefaults for the one thing we need to persist
/// across launches: the passport token issued at registration. Anything
/// richer (offline cache of stamps, sync queue) can be added later — for
/// now the server is the source of truth and we always re-fetch on launch.
enum LocalStore {
    private static let passportTokenKey = "passportToken"
    private static let participantNameKey = "participantName"
    private static let participantEmailKey = "participantEmail"
    private static let flightsKey = "flights.v1"
    private static let estimatedCheckoutsKey = "estimatedCheckouts.v1"

    static var passportToken: String? {
        get { UserDefaults.standard.string(forKey: passportTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: passportTokenKey) }
    }

    static var participantName: String? {
        get { UserDefaults.standard.string(forKey: participantNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: participantNameKey) }
    }

    static var participantEmail: String? {
        get { UserDefaults.standard.string(forKey: participantEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: participantEmailKey) }
    }

    /// Flights the customer has added for the challenge day. Source of
    /// truth lives here — the flight-search backend is stateless and
    /// doesn't store per-user itineraries.
    static var flights: [Flight] {
        get {
            guard let data = UserDefaults.standard.data(forKey: flightsKey) else { return [] }
            return (try? JSONDecoder().decode([Flight].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: flightsKey)
        }
    }

    /// Venue IDs whose `checkedOutAt` was auto-estimated by the client
    /// (because the customer forgot to tap "leaving" before the next
    /// check-in). The server has no notion of estimated-vs-manual so we
    /// keep this flag device-side; it drives the caution glyph in the cell
    /// and seeds the edit sheet with the estimate.
    static var estimatedCheckouts: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: estimatedCheckoutsKey) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: estimatedCheckoutsKey)
        }
    }

    static func isCheckoutEstimated(_ venueId: VenueId) -> Bool {
        estimatedCheckouts.contains(venueId.rawValue)
    }

    static func markCheckoutEstimated(_ venueId: VenueId) {
        var s = estimatedCheckouts
        s.insert(venueId.rawValue)
        estimatedCheckouts = s
    }

    /// Called when the user explicitly sets a checkout time (manual tap or
    /// edit) — clears the "estimated" badge.
    static func markCheckoutManual(_ venueId: VenueId) {
        var s = estimatedCheckouts
        s.remove(venueId.rawValue)
        estimatedCheckouts = s
    }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: passportTokenKey)
        d.removeObject(forKey: participantNameKey)
        d.removeObject(forKey: participantEmailKey)
        d.removeObject(forKey: flightsKey)
        d.removeObject(forKey: estimatedCheckoutsKey)
    }
}
