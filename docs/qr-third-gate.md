# Plan: QR-token third gate + Universal Links

Future feature. Backed out before shipping so we can rethink the venue-side rollout (printed-QR logistics, secret rotation, no-app-installed UX). This doc captures the design so the work is recoverable later without spelunking git history.

A full end-to-end implementation lived briefly on `main` as commit `d15cfe8` and was reverted by the next commit. `git show d15cfe8` is the reference if you want to lift the code back wholesale.

## Why

Today's check-in has two gates: the per-participant passport token (held on the customer's phone) and a CoreLocation geofence (200m around the venue anchor). A determined customer with a spoofed GPS can stamp from anywhere — the 200m radius is loose enough that "I drove past once" can register inside it depending on signal.

Adding a per-venue printed-QR secret as a third gate forces physical presence: you can't stamp without literally reading the QR off the bar. The secret rotates if a photo of the printout leaks.

## Architecture

Three independent gates on `POST /passport/checkin` (and on `POST /passport/register`, since registration is a first-stamp event):

1. **Passport token** — per-participant unguessable string. Already in place.
2. **Geofence** — CoreLocation ↔ Haversine on-device + server-side audit log. Already in place.
3. **Venue QR token** — per-venue secret printed on each bar's QR. NEW. Backend compares against `VENUE_QR_SECRETS` env in constant time; mismatch is a 403.

## URL contract

Each venue's printed QR encodes a Universal Link:

```
https://<ASSOCIATED_DOMAIN>/v/<venueId>?q=<secret>
```

- `<ASSOCIATED_DOMAIN>` — the host serving the backend AND the AASA file. Must be HTTPS, must serve `/.well-known/apple-app-site-association` with no redirects, content-type `application/json`.
- `<venueId>` — `nyc`, `chi`, `nas`, `aus`, or `cha`.
- `<secret>` — opaque token. The backend's `VENUE_QR_SECRETS` env maps each venueId to its current secret; rotate by redeploying env (no code change).

Fallback custom-scheme form (in case AASA cache misbehaves at a venue): `mrp:venue/<venueId>?q=<secret>`. Same in-app parser handles both.

## iOS work

In the iOS app (`passport-ios`):

- [ ] `Passport/QRScannerView.swift` — `AVCaptureSession` + `AVCaptureMetadataOutput` SwiftUI wrapper. Single-shot per session, with a reticle + cancel overlay.
- [ ] `Passport/DeepLink.swift` — parser for both the Universal Links URL and the custom-scheme fallback. Includes a `DeepLinkRouter` `ObservableObject` so `onOpenURL` arrivals route to whichever screen is in front.
- [ ] `Passport/PassportApp.swift` — pipe `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` through the router.
- [ ] `Passport/PassportView.swift` — tap-cell on unstamped venue opens the scanner sheet. Replace `inlineCheckin(venue:)` with `performCheckin(scan:)` that threads the `venueQrToken` into `PendingCheckin`. Also react to `DeepLinkRouter.pendingScan` for system-camera Universal-Link arrivals.
- [ ] `Passport/RegisterView.swift` — venue picker replaced with a "Scan venue QR" CTA. Submit gated on a captured scan; "Re-scan" affordance for the tap-the-wrong-QR case.
- [ ] `Passport/Models.swift` — `RegisterRequest` + `CheckinRequest` carry `venueQrToken`.
- [ ] `Passport/CheckinQueue.swift` — `PendingCheckin.venueQrToken` (optional, only set on `.checkin` rows). Older queued rows without it drop on drain.
- [ ] `Passport/Passport.entitlements` (new) — `applinks:$(ASSOCIATED_DOMAIN)`. Wire in via `project.yml`'s `CODE_SIGN_ENTITLEMENTS` build setting.
- [ ] `Configuration/Debug.xcconfig` + `Release.xcconfig` — new `ASSOCIATED_DOMAIN` build setting.
- [ ] `Passport/Info.plist` + `project.yml` — add `NSCameraUsageDescription` ("Reads the QR code on each venue's bar…").

Anti-spoof: don't trust the cell the user tapped — only the venue encoded inside the QR can drive a stamp. The cell tap is a hint, the scan is canonical. If they're already stamped at the scanned venue, short-circuit to a friendly alert before enqueueing (the queue and the server's unique constraint catch it too, but the UX is nicer up front).

## Backend work

In the passport backend (`mothers/passport`):

- [ ] `src/lib/venues.ts` — `verifyVenueQrToken(venueId, provided): { ok: true } | { ok: false; reason: "not_configured" | "mismatch" }` using `node:crypto` `timingSafeEqual` so the secret check isn't a timing side-channel.
- [ ] `src/routes/checkin.ts` — require `venueQrToken` in the body; 403 on mismatch, 503 if `VENUE_QR_SECRETS` isn't configured for the venue.
- [ ] `src/routes/register.ts` — same gate. Registration is a first-stamp event, so it runs the same three checks.
- [ ] `src/routes/aasa.ts` (new) — serves `/.well-known/apple-app-site-association` (and the legacy `/apple-app-site-association` path) declaring `/v/*` as a Universal Link target. Returns 503 if `APPLE_TEAM_ID` isn't set so a misconfig is loud, not silent.
- [ ] `src/env.ts` — new `APPLE_TEAM_ID` + `IOS_BUNDLE_ID` keys.
- [ ] `src/index.ts` — register the new route.

Sample AASA body:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<APPLE_TEAM_ID>.com.mothersruin.passport"],
        "components": [
          { "/": "/v/*", "comment": "Venue check-in" }
        ]
      }
    ]
  }
}
```

## Universal Links specifics

- Apple requires HTTPS, no redirects, content-type `application/json` (no `application/pkcs7-signed-data` signed format — that was iOS 8/9).
- iOS caches the AASA file aggressively; rotating which paths open the app means waiting out the cache or reinstalling the app on test devices.
- Universal Links do NOT trigger from `localhost`. Dev testing of the deep-link path needs a TLS-fronted tunnel (ngrok https URL, staging host) — the in-app scanner is the dev-friendly fallback.
- Tap-test from Messages or Notes is the canonical way to verify a Universal Link is wired; tapping in Safari is unreliable because of Safari's smart-banner heuristics.

## Open questions / risks

1. **Printed-QR logistics.** Who prints them, who posts them, how often do they rotate? A leaked photo of any printout = free check-ins at that venue until rotation.
2. **Lost-secret recovery.** If a staff member rotates `VENUE_QR_SECRETS` mid-shift, in-flight queued check-ins on customer phones will 403 when they drain. Worth thinking about a grace window (accept previous secret for N minutes) or just accepting the rare false-rejection.
3. **No-app-installed UX.** A customer who scans the QR with a system camera and doesn't have the app installed lands on `/v/:venueId?q=:secret`. Currently that page is a skeleton "register / open passport" link — for a public-facing rollout it needs to be a polished install prompt with the App Store link, plus a fallback web check-in if we want to support no-app participation.
4. **Multi-app conflict.** If the bartender app (`validator`) ever needs to read these same QRs, the Universal Links entitlement collision needs handling — Apple resolves to the first-installed-app by default.
5. **Static secrets vs. signed tokens.** Rotating env-driven secrets is fine for a one-day event. For an ongoing program, signed JWTs with `venueId` + `notBefore` / `notAfter` claims would let the QR be public without leaking long-lived secrets.

## Why backed out

POC built fine but rolling it out depends on physical-world coordination (printing, rotation, training staff) that we haven't decided yet. Holding the iOS + backend code in a recoverable shape rather than letting it ship half-finished and rot.
