# Passport — iOS

iOS client for the Mother's Ruin Mother's Day Challenge — a location-verified bar-crawl passport across the five Mother's Ruin venues. Pairs with the `mothers/passport` Node/Fastify backend. POC built to pitch the May 9, 2027 challenge.

## Flow

1. **First launch** → scan the venue's printed QR (system camera, or the in-app scanner) to capture the venue + secret token. The Universal Link drops you on the register form with the venue already locked. Fill in name + email and submit; the backend verifies passport token, geofence, and QR secret in one go and issues a `passportToken`.
2. **Steady state** → passport view pulls `GET /passport/me/:token` and renders the 5-venue stamp grid. Charleston required, two more for the entry tier.
3. **Check in** → at the next venue, scan its printed QR. The Universal Link opens the app and triggers the check-in flow directly; or, from inside the app, tap a venue cell to launch the in-app scanner. Either path: app grabs a CoreLocation fix, runs the client-side geofence gate, and enqueues a check-in (token + scanned venueId + scanned qrToken) on `CheckinQueue`. The queue drains to `POST /passport/checkin` and retries on network failure.
4. **Claim** → once eligible, `ClaimCardView` posts to the wallet-card backend's `POST /signup/request` for an Add-to-Wallet link, then marks the passport complete server-side.

## Verification model

Three independent gates per check-in (and per register, since registration is a first-stamp event):

1. **Passport token** — per-participant unguessable string issued at registration. Lives in `UserDefaults` on one device.
2. **Geofence** — CoreLocation reports lat/lon; we verify the device is within 200m of the venue's anchor via Haversine (`CLLocation.distance`). The client gate is the bouncer — out-of-range submissions never hit the network. The server runs the same check and is the source of truth.
3. **Venue QR token** — per-venue secret printed on each bar's QR. Customers can't fake a check-in from outside the bar with spoofed location because they don't have the QR's token. The backend compares against `VENUE_QR_SECRETS` env in constant time; mismatch is a 403.

The backend's `Venues` list and the client's `Venues.anchors` must stay in sync. Drift only changes what the server logs as `withinGeofence`; the gating decision happens on-device. The QR secrets are server-side only — the iOS client just relays whatever string the QR encoded.

## Universal Links

Each venue's printed QR encodes a URL of the form:

```
https://<ASSOCIATED_DOMAIN>/v/<venueId>?q=<secret>
```

The backend serves `/.well-known/apple-app-site-association` declaring this app as the owner of `/v/*` paths under that host. With the app installed, iOS intercepts the link and routes it to `PassportApp`'s `onOpenURL`, which parks the parsed `(venueId, qrToken)` on the shared `DeepLinkRouter`. Whichever screen is in front (register if new, passport view if returning) consumes it and runs its flow.

Without the app, the URL falls through to the backend's venue landing page (`GET /v/:venueId`), which prompts an install.

In dev: Universal Links require HTTPS, so `localhost` won't trigger them. The in-app scanner is the dev-friendly path; system-camera scans need a real TLS host (ngrok, staging) pointing at the backend.

## Setup

### Prerequisites
- macOS with Xcode 15+
- iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Run it

```bash
cd passport-ios

# Edit Configuration/Debug.xcconfig and Release.xcconfig:
#   API_BASE_URL           passport backend host
#   WALLET_API_BASE_URL    wallet-card backend host
#   ASSOCIATED_DOMAIN      Universal Links host (must serve the AASA file
#                          at /.well-known/apple-app-site-association)

xcodegen
open Passport.xcodeproj
```

Hit ▶. First check-in prompts for camera (for the QR scan) and location.

### Configuration

Backend hosts and the Universal Links domain are read at runtime from `Info.plist` keys (`APIBaseURL`, `WalletAPIBaseURL`) and from the entitlements file (`com.apple.developer.associated-domains`), populated at build time by the xcconfig for the active build configuration. To change a host, edit the xcconfig and rebuild — no source changes, no plist diff.

Drop one of `Passport/SimulatorLocations/*.gpx` into the simulator's Debug → Location menu to test the geofence at each venue without leaving your desk.

## Backend contract

Mirrors `mothers/passport/src/routes/`:

```
POST /passport/register            { name, email, phone?, venueId, venueQrToken, latitude, longitude }
POST /passport/checkin             { passportToken, venueId, venueQrToken, latitude, longitude }
GET  /passport/me/:token           → { passport, stamps, eligibleTier }
POST /passport/me/:token/start     marks the customer's day as started (idempotent)
POST /passport/me/:token/checkout  records `checkedOutAt` for a venue
POST /passport/me/:token/complete  closes out the passport with the awarded tier
POST /passport/me/:token/flights   replaces the customer's flight itinerary
POST /flights/search               proxy to the upstream flight-search service
GET  /.well-known/apple-app-site-association   AASA file for Universal Links
GET  /v/:venueId?q=:secret         venue landing page; the printed QR target
```

`POST /signup/request` on the wallet backend is what `ClaimCardView` calls at claim time.

## Permissions

- **Camera** — to scan the venue's printed QR code (`AVCaptureSession` in `QRScannerView`).
- **Location When-In-Use** — to verify the phone is at the venue at check-in.

Both prompts have copy on `Info.plist` that explains the use case.

## Files

```
project.yml                  XcodeGen spec; iOS 16+, camera + location, associated-domains entitlement
Configuration/
  Debug.xcconfig             dev build URLs + ASSOCIATED_DOMAIN
  Release.xcconfig           release build URLs + ASSOCIATED_DOMAIN (placeholder)
Passport/
  Passport.entitlements      associated-domains entitlement (applinks:$(ASSOCIATED_DOMAIN))
  PassportApp.swift          @main entry; routes onOpenURL into DeepLinkRouter
  ContentView.swift          routes between RegisterView and PassportView based on LocalStore
  RegisterView.swift         scan venue QR → name / email / submit → POST /passport/register
  PassportView.swift         5-venue stamp grid, tier eligibility, scanner-driven check-in
  ClaimCardView.swift        Apple Wallet claim flow once eligible
  ChallengeWindow.swift      challenge-date gating (pre/during/post)
  ChallengeClosedView.swift  read-only summary once the day is over
  EditCheckoutSheet.swift    manual edit of a previously-recorded checkout time
  FlightsView.swift          itinerary list + add-flight search form
  FlightsAPI.swift           client for the backend's flight-search proxy
  FlightCountdownView.swift  next-flight countdown card on the passport
  Flights.swift              local Flight model + request/response shapes
  QRScannerView.swift        AVCaptureSession-based QR scanner
  DeepLink.swift             URL parser for the venue QR + DeepLinkRouter ObservableObject
  CheckinQueue.swift         offline buffer; drains check-ins / checkouts with retry
  LocationManager.swift      one-shot async/await wrapper over CLLocationManager
  Venues.swift               anchor coords + 200m Haversine geofence (mirrors backend)
  APIClient.swift            URLSession + JSON to the passport backend
  LocalStore.swift           UserDefaults wrapper (token, name, email, flights)
  Config.swift               reads backend URLs from Info.plist
  Models.swift               VenueId, EligibleTier, request/response Codables
  SafariSheet.swift          in-app SFSafariViewController for the T&C link
  Brand.swift                color palette
  Info.plist                 camera + location usage strings, ATS exception for localhost
  Assets.xcassets/           app icon + brand logo + LaunchBackground color
  SimulatorLocations/        per-venue GPX files for Xcode's location simulator
```

## TODO before it's real

- [ ] Real T&C URL (placeholder points at `docusign.com`).
- [ ] Surface "scanned QR doesn't match the venue you're standing next to" as its own client-side check — currently caught only by the server's geofence + QR token mismatch.
- [ ] Ship rotating QR secrets — `VENUE_QR_SECRETS` is static; rotating per-day or per-shift narrows the window for a leaked token.

## Debug-only escape hatches

- `PassportView` has a "Sign out (testing)" link gated behind `#if DEBUG`. Production has no sign-out — one passport per device is the model.
