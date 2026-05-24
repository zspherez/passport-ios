import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .invalidResponse: return "Unexpected response from the server."
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        }
    }
}

enum APIClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    private static let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let isoEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func register(_ body: RegisterRequest) async throws -> RegisterResponse {
        try await post(path: "/passport/register", body: body)
    }

    static func checkin(_ body: CheckinRequest) async throws -> CheckinResponse {
        try await post(path: "/passport/checkin", body: body)
    }

    static func passport(token: String) async throws -> PassportSummary {
        try await get(path: "/passport/me/\(token)")
    }

    /// Posts the completed-challenge claim to the wallet-card backend.
    /// Lives on a different base URL (Config.walletApiBaseURL) since this is
    /// a different system, but the request/response shape mirrors what the
    /// wallet's web form sends.
    static func claimWalletCard(_ body: WalletSignupRequest) async throws -> WalletSignupResponse {
        try await post(baseURL: Config.walletApiBaseURL, path: "/signup/request", body: body)
    }

    /// Marks the passport as completed on the passport backend, mirroring
    /// `awardedTier` from whatever wallet card the customer just claimed.
    /// Called right after `claimWalletCard` succeeds so the passport reflects
    /// the closeout without a staff member firing the admin endpoint.
    /// `awardedTier` must be one of: "gold", "gold_tattoo", "black",
    /// "black_flightsuit".
    static func completePassport(token: String, awardedTier: String) async throws -> CompletePassportResponse {
        try await post(path: "/passport/me/\(token)/complete",
                       body: CompletePassportRequest(awardedTier: awardedTier))
    }

    /// Stamps `participants.started_at` with NOW on first call. On any
    /// repeat call the server returns 409 with the original timestamp;
    /// rather than treat that as an error we decode the response and let
    /// the caller move on — the customer's day has already begun.
    static func startPassport(token: String) async throws -> StartPassportResponse {
        do {
            return try await post(
                path: "/passport/me/\(token)/start",
                body: EmptyBody()
            )
        } catch APIError.server(let msg) where msg.lowercased().contains("already started") {
            // Server's 409 came through humanReadableError as the literal
            // string "Already started"; the timestamp inside the JSON has
            // already been discarded. The client will pick the actual value
            // back up on the next /passport/me fetch.
            return StartPassportResponse(ok: false, startedAt: nil)
        }
    }

    /// Tap-to-leave: records `checkins.checked_out_at` for the given
    /// (passport, venue). Idempotent — the server returns the existing row
    /// unchanged if a checkout already exists.
    static func checkout(token: String, venueId: VenueId) async throws -> CheckoutResponse {
        try await post(
            path: "/passport/me/\(token)/checkout",
            body: CheckoutRequest(venueId: venueId)
        )
    }

    /// Edits a previously-recorded checkout time. Used both to backfill a
    /// forgotten checkout and to correct an auto-estimated value the
    /// customer wants to nudge.
    static func editCheckout(token: String, venueId: VenueId, checkedOutAt: Date) async throws -> CheckoutResponse {
        try await post(
            path: "/passport/me/\(token)/checkout/edit",
            body: CheckoutEditRequest(venueId: venueId, checkedOutAt: checkedOutAt)
        )
    }

    /// Replace-all upload of the customer's flight itinerary. Called at
    /// claim time when the "Submit my flight itinerary" checkbox is on.
    static func uploadFlights(token: String, flights: [Flight]) async throws -> FlightsUploadResponse {
        let payload = FlightsUploadRequest(
            flights: flights.map {
                FlightUploadItem(
                    flightCodes: $0.flightCodes,
                    originAirport: $0.originAirport,
                    destinationAirport: $0.destinationAirport,
                    departureAt: $0.departureAt,
                    arrivalAt: $0.arrivalAt,
                    durationMinutes: $0.durationMinutes
                )
            }
        )
        return try await post(path: "/passport/me/\(token)/flights", body: payload)
    }

    // MARK: - Plumbing

    private static func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: Config.apiBaseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await execute(req)
    }

    private static func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        try await post(baseURL: Config.apiBaseURL, path: path, body: body)
    }

    private static func post<Body: Encodable, T: Decodable>(baseURL: String, path: String, body: Body) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try isoEncoder.encode(body)
        return try await execute(req)
    }

    private static func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 {
            throw APIError.server(humanReadableError(from: data, status: http.statusCode))
        }
        do {
            return try isoDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    /// Pull the most useful message out of a failing JSON response so error
    /// states render as plain English instead of `HTTP 403: {"error":"..."}`.
    /// Handles three shapes the backend produces:
    ///   1. {"error":"plain string"}                       → the string
    ///   2. {"error":{"formErrors":[...],"fieldErrors":{...}}}
    ///                                                     → first field error
    ///   3. anything else                                  → HTTP <code>
    private static func humanReadableError(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = json["error"] as? String, !s.isEmpty {
                return s
            }
            if let nested = json["error"] as? [String: Any] {
                if let fieldErrors = nested["fieldErrors"] as? [String: [String]],
                   let firstField = fieldErrors.first,
                   let firstMsg = firstField.value.first {
                    return "\(firstField.key): \(firstMsg)"
                }
                if let formErrors = nested["formErrors"] as? [String],
                   let firstForm = formErrors.first {
                    return firstForm
                }
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return "Request failed (HTTP \(status))"
    }
}
