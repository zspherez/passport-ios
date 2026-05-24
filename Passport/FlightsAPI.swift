import Foundation

/// Client for the passport backend's flight-search proxy (which in turn
/// forwards to the Python sidecar that wraps fli). All flight traffic
/// shares the same host as the rest of the passport API — no separate
/// service to point at, no third-party domain in the client.
enum FlightsAPI {
    private static var baseURL: URL {
        URL(string: Config.apiBaseURL)!
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        return URLSession(configuration: cfg)
    }()

    private static let encoder: JSONEncoder = JSONEncoder()
    private static let decoder: JSONDecoder = JSONDecoder()

    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parses the upstream ISO-without-offset strings ("2026-05-13T14:35:00")
    /// as if they were UTC. They're really local-to-airport, but we don't
    /// have the airport's tz on the iOS side — for countdown math the user
    /// is in the same place as the airport so device-local rendering of a
    /// UTC-parsed timestamp produces the wrong wall-clock. To compensate,
    /// `parseAirportLocal` interprets the string as already-local and
    /// returns a Date that, when formatted in the device's timezone, shows
    /// the same HH:MM as the original. Good enough for countdown UX.
    private static let airportLocalParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        return f
    }()

    private static let airportNoTZParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseAirportLocal(_ s: String) -> Date? {
        airportNoTZParser.date(from: s) ?? airportLocalParser.date(from: s)
    }

    /// Look up non-stop scheduled flights between two metros on a date.
    /// `origins`/`destinations` are arrays of IATA codes so multi-airport
    /// cities (NYC, Chicago) cover every reasonable departure/arrival in
    /// a single query. Returned results are scheduled times only.
    static func search(origins: [String], destinations: [String], date: Date) async throws -> [FlightSearchResult] {
        let req = FlightSearchRequest(
            origins: origins.map { $0.uppercased() },
            destinations: destinations.map { $0.uppercased() },
            travelDate: ymdFormatter.string(from: date),
            maxStops: "NON_STOP"
        )
        var urlReq = URLRequest(url: baseURL.appendingPathComponent("flights/search"))
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = try encoder.encode(req)

        let (data, response) = try await session.data(for: urlReq)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode >= 400 {
            throw APIError.server("Flight search failed (HTTP \(http.statusCode)).")
        }
        return try decoder.decode([FlightSearchResult].self, from: data)
    }

    /// Build the local `Flight` model from a search result the user tapped.
    /// We pick the first leg's departure airport + first/last datetime so
    /// the local representation is a single edge in their itinerary even
    /// for multi-leg connections.
    static func flight(from result: FlightSearchResult) -> Flight? {
        guard
            let firstLeg = result.legs.first,
            let lastLeg = result.legs.last,
            let dep = parseAirportLocal(firstLeg.departureDatetime),
            let arr = parseAirportLocal(lastLeg.arrivalDatetime)
        else { return nil }
        return Flight(
            id: UUID(),
            flightCodes: result.flightCodes,
            originAirport: firstLeg.departureAirport,
            destinationAirport: lastLeg.arrivalAirport,
            departureAt: dep,
            arrivalAt: arr,
            durationMinutes: result.duration
        )
    }
}
