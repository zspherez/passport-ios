import Foundation

enum VenueId: String, Codable, CaseIterable, Identifiable {
    case nyc, chi, nas, aus, cha

    /// Used by SwiftUI `sheet(item:)` and `fullScreenCover(item:)` so we
    /// can drive a single sheet from "which venue did the user tap".
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nyc: return "NYC"
        case .chi: return "Chicago"
        case .nas: return "Nashville"
        case .aus: return "Austin"
        case .cha: return "Charleston"
        }
    }

    /// Charleston is required by the challenge rules; everything else is optional.
    var isRequired: Bool { self == .cha }
}

enum EligibleTier: String, Codable {
    case none
    case gold
    case black
    case blackFlightsuit = "black_flightsuit"

    var displayName: String {
        switch self {
        case .none: return "Keep collecting stamps"
        case .gold: return "Gold card eligible"
        case .black: return "Black card eligible"
        case .blackFlightsuit: return "Black + flight suit eligible"
        }
    }
}

// MARK: - API request bodies

struct RegisterRequest: Codable {
    let name: String
    let email: String
    let phone: String?
    /// Where the customer plans to start on challenge day. Stored as a
    /// hint on the server (`participants.registered_venue_id`) but not
    /// gating anything — they can ultimately start their first stamp at
    /// any venue. No location capture at registration.
    let venueId: VenueId
}

struct CheckinRequest: Codable {
    let passportToken: String
    let venueId: VenueId
    let latitude: Double
    let longitude: Double
}

// MARK: - API responses

struct RegisterResponse: Codable {
    let passportToken: String
    let resumed: Bool
}

struct StampSummary: Codable, Equatable {
    let venueId: VenueId
    let checkedInAt: Date
    /// Null while the customer is "at" the venue; set when they tap to leave
    /// (or when the next check-in auto-estimates a value for a forgotten
    /// check-out). The client distinguishes auto-estimates from explicit
    /// values via a separate local flag (see CheckinQueue), not from the
    /// server payload — the server treats both the same.
    let checkedOutAt: Date?
}

struct CheckinResponse: Codable {
    let ok: Bool
    let venueId: VenueId
    let distanceMeters: Int
    let stamps: [StampSummary]
}

// MARK: - Wallet-card signup (mothers/backend's /signup/request)

/// City presets the wallet signup form offers. "other" picks a free-form
/// string handled separately in the UI.
enum HomeCity: String, Codable, CaseIterable {
    case nashville = "Nashville"
    case austin = "Austin"
    case charleston = "Charleston"
    case nyc = "NYC"
    case chicago = "Chicago"
    case other
}

struct WalletSignupRequest: Codable {
    let name: String
    let displayName: String
    let email: String
    let homeCity: String
    /// "black" or "gold" — this year's card.
    let cardType: String
    /// 3 / 4 / 5 (or whatever the participant earned).
    let locationsVisited: Int
    /// Subset of the years 2023..<currentYear the participant has previously
    /// completed. Server validates the membership in `priorYearsList()`.
    let priorYears: [Int]
}

struct WalletSignupResponse: Codable {
    let requestId: String
    let userId: String?
    let status: String
    let autoApproved: Bool?
    let installUrl: String?
    let message: String?
}

/// Mirrors `POST /passport/me/:token/complete`. `awardedTier` must match
/// the backend's allow-list: "gold" | "gold_tattoo" | "black" | "black_flightsuit".
struct CompletePassportRequest: Codable {
    let awardedTier: String
}

struct CompletePassportResponse: Codable {
    let ok: Bool
    let id: String?
    let completedAt: Date?
    let awardedTier: String?
}

/// Sentinel body for endpoints that take no payload but still need to be
/// POSTed (the helper signature is generic over `Body: Encodable`).
struct EmptyBody: Codable {}

/// Response from `POST /passport/me/:token/start`. The server returns the
/// new startedAt on first call and a 409 (with the existing startedAt) on
/// any subsequent call — APIClient surfaces both as a `StartPassportResponse`
/// so the client can reconcile state either way.
struct StartPassportResponse: Codable {
    let ok: Bool?
    let startedAt: Date?
}

struct CheckoutRequest: Codable {
    let venueId: VenueId
}

/// Mirrors the `checkins` row returned by both /checkout endpoints.
/// Includes everything we need to merge the change back into the local
/// stamp list without a full refetch.
struct CheckoutResponse: Codable {
    let id: String
    let participantId: String
    let venueId: VenueId
    let checkedInAt: Date
    let checkedOutAt: Date?
}

struct CheckoutEditRequest: Codable {
    let venueId: VenueId
    /// ISO 8601 with offset — JSONEncoder.dateEncodingStrategy = .iso8601 by
    /// our default config produces this shape.
    let checkedOutAt: Date
}

/// Single flight in the upload payload. Mirrors the backend `flightItemSchema`.
struct FlightUploadItem: Codable {
    let flightCodes: String
    let originAirport: String
    let destinationAirport: String
    let departureAt: Date
    let arrivalAt: Date
    let durationMinutes: Int?
}

struct FlightsUploadRequest: Codable {
    let flights: [FlightUploadItem]
}

struct FlightsUploadResponse: Codable {
    let ok: Bool
    let count: Int
}

struct PassportSummary: Codable {
    let passport: Passport
    let venues: [VenueStatus]
    let stamps: [StampSummary]
    let eligibleTier: EligibleTier
    let charlestonStamped: Bool

    struct Passport: Codable {
        let id: String
        let name: String
        let email: String
        let registeredVenueId: VenueId
        let createdAt: Date
        /// Set when the customer taps the "Start the day" button before
        /// heading to their first venue. Null until pressed; the stats card
        /// at the end uses this as the duration anchor.
        let startedAt: Date?
        let completedAt: Date?
        let awardedTier: String?
    }

    struct VenueStatus: Codable {
        let id: VenueId
        let name: String
        let city: String
        let stamped: Bool
    }
}
