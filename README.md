# Mother's Day Challenge Passport — iOS

SwiftUI client for a location-verified, multi-venue "passport" event.
Customers register on first launch, then visit a set of bar/restaurant
venues across the country on challenge day and collect a stamp at each
one by scanning the venue's QR and proving (via CoreLocation + a server-
side geofence) that their phone is physically inside.

**Status:** proof-of-concept built to pitch the Mother's Ruin team for
the May 9 Mother's Day Challenge. Pairs with the `mothers/passport`
Node/Fastify backend. Same xcodegen + SwiftUI conventions as the
`validator/` app.

## Setup

```bash
cd passport-ios

# 1. Point Debug/Release builds at your backend.
#    Edit Configuration/Debug.xcconfig   → API_BASE_URL, WALLET_API_BASE_URL
#    Edit Configuration/Release.xcconfig → API_BASE_URL, WALLET_API_BASE_URL

# 2. Generate the Xcode project.
xcodegen          # produces Passport.xcodeproj from project.yml
open Passport.xcodeproj
```

The xcconfig values land in Info.plist (`APIBaseURL`, `WalletAPIBaseURL`)
and are read at runtime by `Config.swift`. To change a host, edit the
xcconfig for that configuration and rebuild — no source changes.

## Files

```
project.yml                  xcodegen config; iOS 16+ target, camera + location permissions
Configuration/
  Debug.xcconfig             dev build URLs (localhost by default)
  Release.xcconfig           production build URLs (placeholder)
Passport/
  PassportApp.swift          @main entry
  ContentView.swift          routes between RegisterView and PassportView based on LocalStore
  RegisterView.swift         name / email / phone / initial venue → POST /passport/register
  PassportView.swift         5-venue stamp grid, tier eligibility, "Check in here" button
  CheckinFlow.swift          full-screen modal: QR scan → CoreLocation fix → POST /passport/checkin
  QRScannerView.swift        AVCaptureSession wrapper, accepts the venue's printed QR
  LocationManager.swift      one-shot async/await wrapper over CLLocationManager
  APIClient.swift            URLSession + JSON to the passport backend
  Models.swift               VenueId, EligibleTier, request/response Codables
  LocalStore.swift           UserDefaults wrapper (passport token + cached name/email)
  Config.swift               reads backend base URLs from Info.plist (xcconfig-driven)
  Info.plist                 NSCameraUsageDescription + NSLocationWhenInUseUsageDescription
  Assets.xcassets/           empty asset catalog scaffold
```

## Flows

**First launch** → `RegisterView`. Captures name + email + which venue the customer is at right now, hits `POST /passport/register`, stores the returned `passportToken` in `UserDefaults`, drops into the passport.

**Steady state** → `PassportView`. Pulls `/passport/me/<token>` on appear, renders the 5 venues as a stamp grid (Charleston flagged required), shows tier eligibility, exposes a "Check in here" button.

**Check in** → `CheckinFlow` modal:
1. **QR scan**. Accepts either `mrp:<venueId>:<token>` or a URL containing `/v/<venueId>?q=<token>` (matches the printed QR pattern the backend's `/v/:venueId` route expects).
2. **Location fix** via `LocationManager.oneShot()`. Requests When-In-Use permission first time; one fresh sample.
3. **POST `/passport/checkin`** with the QR token + reported lat/lon. Server runs the three-gate verification (passport token → QR secret → geofence) and returns the updated stamp list.
4. Success view auto-dismisses after ~2.5s; passport refreshes.

## Backend expectations

Mirrors `mothers/passport/src/routes/`:

- `POST /passport/register`  body `{ name, email, phone?, venueId }`
- `POST /passport/checkin`   body `{ passportToken, venueId, venueQrToken, latitude, longitude }`
- `GET  /passport/me/:token` returns participant + per-venue stamp status + eligible tier

## Permissions

- **Camera** — to scan venue QR codes.
- **Location When-In-Use** — to verify the phone is at the venue at check-in.

Both prompts live on the Info.plist with copy that explains the use case.

## Known TODO

- [ ] Settings screen with proper sign-out (today it's a dev "Sign out (testing)" link).
- [ ] Better empty / error states once the registration backend rejects (e.g., the email is already in use).
- [ ] Offline buffering — if a check-in fails because of network, queue and retry like the validator's `SyncEngine`.
- [ ] Universal Links so a printed QR opens directly into the check-in flow when the app is installed.
- [ ] App icon + launch screen artwork.
