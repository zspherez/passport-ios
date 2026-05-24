import Foundation

/// Mother's Ruin venue → all reasonable airport IATAs. Multi-airport cities
/// (NYC, Chicago) include every metro option. Used by the auto-checkout
/// estimator (matches a recorded flight's origin/destination against the
/// venue's airport set) and as the source of `AirportOption.all` below.
extension VenueId {
    var airports: [String] {
        switch self {
        case .nyc: return ["JFK", "LGA", "EWR"]
        case .chi: return ["ORD", "MDW"]
        case .nas: return ["BNA"]
        case .aus: return ["AUS"]
        case .cha: return ["CHS"]
        }
    }
}

/// One IATA code paired with the venue it belongs to. Powers the airport
/// picker in FlightsView — listing every airport lets the customer pin a
/// specific origin/destination ("LGA → MDW") instead of widening the
/// search to the whole metro and wading through a long result list.
struct AirportOption: Hashable, Identifiable {
    let code: String
    let venue: VenueId
    var id: String { code }
    /// "JFK · NYC" — short enough to render in a menu cell without truncating.
    var displayLabel: String { "\(code) · \(venue.displayName)" }

    static let all: [AirportOption] = VenueId.allCases.flatMap { v in
        v.airports.map { AirportOption(code: $0, venue: v) }
    }
}

/// A flight the customer has added to their itinerary. Persisted locally
/// (see LocalStore.flights); the flight-search backend is stateless, so
/// the source of truth for "my trip" is the device.
struct Flight: Codable, Equatable, Identifiable {
    let id: UUID
    let flightCodes: String          // e.g. "AA1234" or "AA1234, DL5678" for multi-leg
    let originAirport: String        // IATA
    let destinationAirport: String   // IATA
    let departureAt: Date
    let arrivalAt: Date
    /// Minutes from departure to arrival, gate-to-gate. Includes connection
    /// time for multi-leg flights.
    let durationMinutes: Int
}

// MARK: - Flight-search request/response shapes

/// Mirrors the FastAPI `SearchRequest` model — only the fields we send are
/// listed; defaults on the server side cover the rest. `origins` and
/// `destinations` are arrays so a single NYC→CHI search hits every JFK/
/// LGA/EWR → ORD/MDW combination.
struct FlightSearchRequest: Codable {
    let origins: [String]
    let destinations: [String]
    /// "YYYY-MM-DD" per the server.
    let travelDate: String
    let maxStops: String

    enum CodingKeys: String, CodingKey {
        case origins
        case destinations
        case travelDate = "travel_date"
        case maxStops = "max_stops"
    }
}

/// Top-level result from POST /api/search. The `flight_codes` field is a
/// comma-separated string for multi-leg itineraries; for the bar challenge
/// use-case we only show non-stop results, so it'll typically be one code.
struct FlightSearchResult: Codable, Identifiable {
    var id: String { "\(flightCodes)|\(departureTime)|\(legs.first?.departureDatetime ?? "")" }

    let origin: String
    let destination: String
    let flightCodes: String
    /// "HH:MM" — date is implied from the search date.
    let departureTime: String
    let arrivalTime: String
    let price: Double
    let stops: Int
    /// Minutes (server returns int).
    let duration: Int
    let legs: [FlightSearchLeg]

    enum CodingKeys: String, CodingKey {
        case origin, destination
        case flightCodes = "flight_codes"
        case departureTime = "departure_time"
        case arrivalTime = "arrival_time"
        case price, stops, duration, legs
    }
}

struct FlightSearchLeg: Codable {
    let airline: String
    let flightNumber: String
    let departureAirport: String
    let arrivalAirport: String
    /// ISO 8601 — local airport time. No timezone offset in the string per
    /// the upstream Python `.isoformat()` on naive datetimes; we parse it as
    /// local-to-airport and convert on display.
    let departureDatetime: String
    let arrivalDatetime: String
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case airline
        case flightNumber = "flight_number"
        case departureAirport = "departure_airport"
        case arrivalAirport = "arrival_airport"
        case departureDatetime = "departure_datetime"
        case arrivalDatetime = "arrival_datetime"
        case duration
    }
}
