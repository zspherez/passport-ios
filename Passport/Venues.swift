import CoreLocation

/// Client-side mirror of `mothers/passport/src/lib/venues.ts`. Coordinates
/// must stay in sync with the backend's `VENUES` list (the audit log on the
/// server uses its own copy for the advisory distance computation, but the
/// gating decision happens here on the device).
///
/// `geofenceMeters` matches the backend's `GEOFENCE_METERS` env default of
/// 200m. Adjusting one without the other will only affect what the server
/// logs as `withinGeofence` — it won't change the client gate.
enum Venues {
    static let geofenceMeters: Double = 200

    struct Anchor {
        let id: VenueId
        let latitude: Double
        let longitude: Double
    }

    static let anchors: [Anchor] = [
        Anchor(id: .cha, latitude: 32.7899039, longitude: -79.9389396),
        Anchor(id: .nyc, latitude: 40.7213363, longitude: -73.9950075),
        Anchor(id: .chi, latitude: 41.9348643, longitude: -87.7165649),
        Anchor(id: .nas, latitude: 36.1761103, longitude: -86.7903022),
        Anchor(id: .aus, latitude: 30.263719,  longitude: -97.728518),
    ]

    static func anchor(for id: VenueId) -> Anchor {
        guard let a = anchors.first(where: { $0.id == id }) else {
            fatalError("Missing anchor for venue \(id.rawValue) — keep Venues.anchors in sync with backend VENUES")
        }
        return a
    }

    /// Distance in meters from the given coords to the venue's anchor.
    /// Uses CLLocation rather than rolling our own Haversine — Apple's
    /// implementation handles the WGS84 spheroid correctly.
    static func distanceMeters(from coord: CLLocationCoordinate2D, to venueId: VenueId) -> Double {
        let a = anchor(for: venueId)
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let there = CLLocation(latitude: a.latitude, longitude: a.longitude)
        return here.distance(from: there)
    }

    /// True if the reported coords are within the geofence radius of the
    /// named venue. Called before any /passport/checkin request so the
    /// network round-trip is reserved for confirmed-in-range submissions.
    static func isWithinGeofence(_ coord: CLLocationCoordinate2D, of venueId: VenueId) -> Bool {
        distanceMeters(from: coord, to: venueId) <= geofenceMeters
    }
}
