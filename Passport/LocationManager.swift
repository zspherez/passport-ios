import CoreLocation
import Foundation

/// Thin wrapper around CLLocationManager that fetches a single position with
/// best accuracy, async/await style. Asks for While-In-Use permission on
/// first call and surfaces the resulting status through a single Swift
/// throwable. Long-running tracking isn't needed here — we only sample once
/// at check-in time.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    enum LocationError: Error, LocalizedError {
        case denied
        case restricted
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Location permission denied. Enable it in Settings to check in."
            case .restricted: return "Location services are restricted on this device."
            case .unavailable(let msg): return msg
            }
        }
    }

    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Request a single fresh fix. Throws if the user denies permission or
    /// if the system can't return a location within ~15 seconds.
    func oneShot() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }

    private func resume(with result: Result<CLLocation, Error>) {
        let cont = continuation
        continuation = nil
        switch result {
        case .success(let loc): cont?.resume(returning: loc)
        case .failure(let err): cont?.resume(throwing: err)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.resume(with: .success(loc)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: .failure(error)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Re-trigger requestLocation if the user just granted us access.
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            Task { @MainActor in
                guard self.continuation != nil else { return }
                manager.requestLocation()
            }
        case .denied:
            Task { @MainActor in self.resume(with: .failure(LocationError.denied)) }
        case .restricted:
            Task { @MainActor in self.resume(with: .failure(LocationError.restricted)) }
        default: break
        }
    }
}
