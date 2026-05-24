# Passport — iOS

iOS client for the Mother's Ruin Mother's Day Challenge — a location-verified bar-crawl passport across the five Mother's Ruin venues. Pairs with the `mothers/passport` Node/Fastify backend. POC built to pitch the May 9, 2027 challenge.

## Flow

1. **First launch** → register with name, email, and which venue you're at right now. Backend issues a `passportToken`, stored in `UserDefaults`.
2. **Steady state** → passport view pulls `GET /passport/me/:token` and renders the 5-venue stamp grid. Charleston required, two more for the entry tier.
3. **Check in** → tap a venue cell. App grabs a single CoreLocation fix, runs the client-side geofence gate (200m, see `Venues.swift`), and enqueues a check-in to `CheckinQueue`. The queue drains to `POST /passport/checkin` in the background and retries on network failure.
4. **Claim** → once eligible, `ClaimCardView` posts to the wallet-card backend's `POST /signup/request` for an Add-to-Wallet link, then marks the passport complete server-side.

## Verification model

Two independent gates per check-in:

1. **Passport token** — per-participant unguessable string issued at registration. Lives in `UserDefaults` on one device.
2. **Geofence** — CoreLocation reports lat/lon; we verify the device is within 200m of the venue's anchor via Haversine (`CLLocation.distance`). The client gate is the bouncer — out-of-range submissions never hit the network. The server runs the same check and is the source of truth.

The backend's `Venues` list and the client's `Venues.anchors` must stay in sync. Drift only changes what the server logs as `withinGeofence`; the gating decision happens on-device.

## Setup

### Prerequisites
- macOS with Xcode 15+
- iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Run it

```bash
cd passport-ios

# Edit Configuration/Debug.xcconfig   (defaults to localhost:3001)
# Edit Configuration/Release.xcconfig (placeholder host — replace before shipping)

xcodegen
open Passport.xcodeproj
```

Hit ▶. First check-in prompts for location.

### Configuration

Backend hosts are read at runtime from `Info.plist` keys (`APIBaseURL`, `WalletAPIBaseURL`), populated at build time by the xcconfig for the active build configuration. To change a host, edit the xcconfig and rebuild — no source changes, no plist diff.

Drop one of `Passport/SimulatorLocations/*.gpx` into the simulator's Debug → Location menu to test the geofence at each venue without leaving your desk.

## Backend contract

Mirrors `mothers/passport/src/routes/`:

```
POST /passport/register            { name, email, phone?, venueId, latitude, longitude }
POST /passport/checkin             { passportToken, venueId, latitude, longitude }
GET  /passport/me/:token           → { passport, stamps, eligibleTier }
POST /passport/me/:token/start     marks the customer's day as started (idempotent)
POST /passport/me/:token/checkout  records `checkedOutAt` for a venue
POST /passport/me/:token/complete  closes out the passport with the awarded tier
POST /passport/me/:token/flights   replaces the customer's flight itinerary
POST /flights/search               proxy to the upstream flight-search service
```

`POST /signup/request` on the wallet backend is what `ClaimCardView` calls at claim time.

## Files

```
project.yml                  XcodeGen spec; iOS 16+, location permission
Configuration/
  Debug.xcconfig             dev build URLs (localhost by default)
  Release.xcconfig           release build URLs (placeholder — replace before shipping)
Passport/
  PassportApp.swift          @main entry
  ContentView.swift          routes between RegisterView and PassportView based on LocalStore
  RegisterView.swift         name / email / venue picker → POST /passport/register
  PassportView.swift         5-venue stamp grid, tier eligibility, inline check-in
  ClaimCardView.swift        Apple Wallet claim flow once eligible
  ChallengeWindow.swift      challenge-date gating (pre/during/post)
  ChallengeClosedView.swift  read-only summary once the day is over
  EditCheckoutSheet.swift    manual edit of a previously-recorded checkout time
  FlightsView.swift          itinerary list + add-flight search form
  FlightsAPI.swift           client for the backend's flight-search proxy
  FlightCountdownView.swift  next-flight countdown card on the passport
  Flights.swift              local Flight model + request/response shapes
  CheckinQueue.swift         offline buffer; drains check-ins / checkouts with retry
  LocationManager.swift      one-shot async/await wrapper over CLLocationManager
  Venues.swift               anchor coords + 200m Haversine geofence (mirrors backend)
  APIClient.swift            URLSession + JSON to the passport backend
  LocalStore.swift           UserDefaults wrapper (token, name, email, flights)
  Config.swift               reads backend URLs from Info.plist
  Models.swift               VenueId, EligibleTier, request/response Codables
  SafariSheet.swift          in-app SFSafariViewController for the T&C link
  Brand.swift                color palette
  Info.plist                 NSLocationWhenInUseUsageDescription, ATS exception for localhost
  Assets.xcassets/           app icon placeholder + brand logo
  SimulatorLocations/        per-venue GPX files for Xcode's location simulator
```

## TODO before it's real

- [ ] QR scan flow — a per-venue printed QR with a secret token would add a third gate against someone driving past a venue with a spoofed location.
- [ ] Universal Links so a printed QR opens directly into the check-in flow when the app is installed.
- [ ] Real T&C URL (placeholder points at `docusign.com`).

## Debug-only escape hatches

- `PassportView` has a "Sign out (testing)" link gated behind `#if DEBUG`. Production has no sign-out — one passport per device is the model.
