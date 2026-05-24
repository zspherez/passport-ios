import SwiftUI

/// Main screen once the participant has registered. Pulls /passport/me/:token
/// on appear (and after every successful check-in), renders the 5 venues as
/// a stamp grid, and exposes the big "Check in here" button that opens the
/// QR + geolocation flow.
struct PassportView: View {
    @State private var summary: PassportSummary?
    @State private var loading = true
    @State private var errorMessage: String?
    /// Venue currently mid-verification (location fetch + geofence check
    /// running). Drives the spinner overlay on the cell and disables
    /// other taps until it resolves.
    @State private var verifyingVenue: VenueId?
    /// Inline check-in error message — surfaces via .alert.
    @State private var checkinError: String?
    @State private var isClaiming = false
    @State private var isManagingFlights = false
    @State private var flights: [Flight] = LocalStore.flights
    /// (venueId, currentValue) for the checkout-edit sheet. Nil when no
    /// sheet is open.
    @State private var editingCheckout: EditingCheckoutTarget?
    @StateObject private var queue = CheckinQueue.shared

    let onReset: () -> Void

    /// Identifiable wrapper so we can drive a sheet(item:) for the edit.
    struct EditingCheckoutTarget: Identifiable {
        var id: VenueId { venueId }
        let venueId: VenueId
        let checkedInAt: Date
        let currentCheckedOutAt: Date
    }

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .task { await refresh() }
        .onChange(of: queue.pending) { _ in
            // Queue drained one or more items in the background — refresh
            // so the (formerly optimistic) stamps land as real ones from
            // the server and the pending indicator clears.
            Task { await refresh() }
        }
        .alert("Can't check in", isPresented: Binding(
            get: { checkinError != nil },
            set: { if !$0 { checkinError = nil } }
        )) {
            Button("OK") { checkinError = nil }
        } message: {
            Text(checkinError ?? "")
        }
        .sheet(item: $editingCheckout) { target in
            EditCheckoutSheet(
                target: target,
                onSave: { newValue in
                    if let token = LocalStore.passportToken {
                        CheckinQueue.shared.enqueueCheckoutEdit(
                            token: token,
                            venueId: target.venueId,
                            newCheckedOutAt: newValue
                        )
                        LocalStore.markCheckoutManual(target.venueId)
                    }
                    editingCheckout = nil
                    Task { await refresh() }
                },
                onCancel: { editingCheckout = nil }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isClaiming) {
            if let summary {
                ClaimCardView(
                    eligibleTier: summary.eligibleTier,
                    locationsVisited: summary.stamps.count,
                    initialName: summary.passport.name,
                    initialEmail: summary.passport.email,
                    initialHomeCity: HomeCity.fromVenue(summary.passport.registeredVenueId),
                    onDismiss: { isClaiming = false }
                )
            }
        }
        .sheet(isPresented: $isManagingFlights) {
            FlightsView(flights: $flights, onDismiss: { isManagingFlights = false })
        }
    }

    @ViewBuilder
    private var content: some View {
        if let summary {
            // Single fixed VStack, no ScrollView — everything has to fit on
            // one standard iPhone screen. Sub-components have been sized
            // accordingly; if you add another row, trim somewhere else.
            VStack(alignment: .leading, spacing: 10) {
                header(for: summary)
                if summary.passport.startedAt == nil && summary.passport.completedAt == nil {
                    startDayButton
                }
                stampGrid(for: summary)
                if summary.passport.completedAt == nil {
                    progressBar(for: summary)
                    flightStrip
                }
                if summary.passport.completedAt != nil {
                    statsCard(for: summary)
                } else if summary.eligibleTier != .none {
                    tierCard(for: summary)
                }
                Spacer(minLength: 0)
                resetButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 6)
        } else if loading {
            VStack(spacing: 14) {
                ProgressView().tint(Brand.gold).scaleEffect(1.2)
                Text("Loading passport…").foregroundStyle(.secondary)
            }
        } else if let errorMessage {
            VStack(spacing: 14) {
                Text("Couldn't load your passport.").font(.headline)
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await refresh() } }
                    .padding(.top, 6)
                    .foregroundColor(.black)
                    .padding()
                    .background(Brand.gold)
                    .cornerRadius(12)
            }
            .padding(24)
        }
    }

    private func header(for summary: PassportSummary) -> some View {
        VStack(spacing: 4) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 110)
            Text(summary.passport.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(.white)
            Text("Mother's Day Challenge Passport")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
    }

    /// Merge server-confirmed stamps with locally-queued ones so the grid
    /// reflects every stamp the user has earned, even those still draining
    /// the queue. Pending stamps render identically to confirmed ones —
    /// from the customer's POV the network round-trip is invisible.
    private struct MergedStamp {
        let venueId: VenueId
        let checkedInAt: Date
        let checkedOutAt: Date?
    }

    private func mergedStamps(for summary: PassportSummary) -> [MergedStamp] {
        // Confirmed stamps first; pending check-ins overlay any venues
        // the server hasn't acknowledged yet. Pending checkout-edits also
        // override their venue's checkedOutAt so the new value renders
        // immediately instead of waiting for the next refresh.
        var byVenue: [VenueId: MergedStamp] = [:]
        for s in summary.stamps {
            byVenue[s.venueId] = MergedStamp(
                venueId: s.venueId,
                checkedInAt: s.checkedInAt,
                checkedOutAt: s.checkedOutAt
            )
        }
        for p in queue.pending {
            switch p.kind {
            case .checkin:
                if byVenue[p.venueId] == nil {
                    byVenue[p.venueId] = MergedStamp(
                        venueId: p.venueId,
                        checkedInAt: p.observedAt,
                        checkedOutAt: nil
                    )
                }
            case .checkout:
                if let existing = byVenue[p.venueId], existing.checkedOutAt == nil {
                    byVenue[p.venueId] = MergedStamp(
                        venueId: existing.venueId,
                        checkedInAt: existing.checkedInAt,
                        checkedOutAt: p.observedAt
                    )
                }
            case .checkoutEdit:
                if let existing = byVenue[p.venueId] {
                    byVenue[p.venueId] = MergedStamp(
                        venueId: existing.venueId,
                        checkedInAt: existing.checkedInAt,
                        checkedOutAt: p.observedAt
                    )
                }
            }
        }
        return byVenue.values.sorted { $0.checkedInAt < $1.checkedInAt }
    }

    private func stampGrid(for summary: PassportSummary) -> some View {
        let ordered = mergedStamps(for: summary)
        let stopByVenue: [VenueId: (number: Int, stamp: MergedStamp)] = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { (idx, s) in
                (s.venueId, (idx + 1, s))
            }
        )
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(summary.venues, id: \.id) { v in
                Button {
                    handleCellTap(venue: v.id, info: stopByVenue[v.id])
                } label: {
                    stampCell(
                        name: v.name,
                        required: v.id.isRequired,
                        stop: stopByVenue[v.id],
                        verifying: verifyingVenue == v.id
                    )
                }
                .buttonStyle(.plain)
                .disabled(cellTapDisabled(for: summary))
            }
        }
    }

    private func cellTapDisabled(for summary: PassportSummary) -> Bool {
        // Lock the grid once the customer has claimed their card — at that
        // point the day is over and we don't want stray taps re-opening
        // closed venues. Also block during an in-flight verify so the
        // customer can't fire concurrent CoreLocation requests.
        summary.passport.completedAt != nil || verifyingVenue != nil
    }

    private func handleCellTap(venue: VenueId, info: (number: Int, stamp: MergedStamp)?) {
        guard LocalStore.passportToken != nil, verifyingVenue == nil else { return }
        if let stamp = info?.stamp {
            if stamp.checkedOutAt == nil {
                // Stamped + still inside → record a check-out.
                if let token = LocalStore.passportToken {
                    CheckinQueue.shared.enqueueCheckout(token: token, venueId: venue)
                    LocalStore.markCheckoutManual(venue)
                }
            } else {
                // Stamped + already checked out → edit the time.
                editingCheckout = EditingCheckoutTarget(
                    venueId: venue,
                    checkedInAt: stamp.checkedInAt,
                    currentCheckedOutAt: stamp.checkedOutAt ?? stamp.checkedInAt
                )
            }
        } else {
            // Not stamped → run the location-verified check-in inline.
            Task { await inlineCheckin(venue: venue) }
        }
    }

    /// Cell-tap check-in: grab a single CoreLocation fix, run the client-
    /// side geofence gate, and enqueue a `PendingCheckin` on success. Done
    /// entirely from the main passport screen — no modal, just a spinner
    /// overlay on the tapped cell while location resolves.
    private func inlineCheckin(venue: VenueId) async {
        guard let token = LocalStore.passportToken else {
            checkinError = "No passport token on this device. Re-register."
            return
        }
        verifyingVenue = venue
        defer { verifyingVenue = nil }
        do {
            let loc = try await LocationManager.shared.oneShot()
            let distance = Venues.distanceMeters(from: loc.coordinate, to: venue)
            if distance > Venues.geofenceMeters {
                checkinError = "Too far from \(venue.displayName) (\(Int(distance)) m away — must be within \(Int(Venues.geofenceMeters)) m)."
                return
            }
            let pending = PendingCheckin(
                id: UUID(),
                kind: .checkin,
                token: token,
                venueId: venue,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                observedAt: Date()
            )
            CheckinQueue.shared.enqueue(pending)
            autoEstimatePreviousCheckout(newlyCheckedInAt: pending)
            await refresh()
        } catch {
            checkinError = error.localizedDescription
        }
    }

    private static let stopTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private func stampCell(name: String,
                           required: Bool,
                           stop: (number: Int, stamp: MergedStamp)?,
                           verifying: Bool) -> some View {
        let stamped = stop != nil
        let isHereNow = stamped && stop?.stamp.checkedOutAt == nil
        let isEstimated = stop.map { LocalStore.isCheckoutEstimated($0.stamp.venueId) } ?? false
        // Three background states so the customer can tell at a glance
        // which venues are done (settled gold), which they're still inside
        // (bright gold + live ring), and which are unvisited (dark).
        let bg: Color = {
            if !stamped { return Color(white: 0.13) }
            return isHereNow ? Brand.gold : Brand.gold.opacity(0.55)
        }()
        return ZStack {
            VStack(spacing: 6) {
                Text(name.replacingOccurrences(of: "Mother's Ruin ", with: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(stamped ? .black : .white)
                HStack(spacing: 4) {
                    Text(stampedLabel(required: required, stop: stop))
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .multilineTextAlignment(.center)
                        .foregroundColor(stamped ? .black.opacity(0.75) : (required ? Brand.gold : .secondary))
                    if isEstimated, stop?.stamp.checkedOutAt != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.65))
                    }
                }
            }
            .opacity(verifying ? 0.35 : 1)

            if verifying {
                VStack(spacing: 6) {
                    ProgressView()
                        .tint(Brand.gold)
                    Text("Verifying…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Brand.gold)
                        .textCase(.uppercase)
                        .tracking(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(bg)
        .overlay(
            // Live ring around the cell the customer is currently sitting
            // inside. Subtle inset stroke so the gold base reads first,
            // ring second.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHereNow ? Color.black.opacity(0.55) : Color.clear,
                    lineWidth: 2
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHereNow {
                // Pulse dot in the top-right corner so the live state is
                // legible without reading the label.
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .padding(10)
            }
        }
        .cornerRadius(12)
    }

    /// Three-state label per the new tap-driven flow:
    ///   - Not stamped → "Tap to check in" (or "Required" / "Not yet" for
    ///     the bare context the user sees pre-tap).
    ///   - Stamped, open → "Checked in HH:MM\nTap again when leaving"
    ///   - Stamped, closed → "In HH:MM\nOut HH:MM"
    private func stampedLabel(required: Bool, stop: (number: Int, stamp: MergedStamp)?) -> String {
        guard let stop else {
            return required ? "Required\nTap to check in" : "Tap to check in"
        }
        let inAt = Self.stopTimeFormatter.string(from: stop.stamp.checkedInAt)
        if let out = stop.stamp.checkedOutAt {
            let outAt = Self.stopTimeFormatter.string(from: out)
            return "Stop #\(stop.number)\nIn \(inAt) · Out \(outAt)"
        }
        return "Stop #\(stop.number)\nIn \(inAt)\nTap again when leaving"
    }

    /// Visual progress through the 5 stops with award milestones at 3/4/5.
    /// Replaces the old "Keep collecting stamps" copy when the customer
    /// hasn't yet earned an eligible tier — and stays visible after that
    /// so they can see how far past their current tier they could push.
    @ViewBuilder
    private func progressBar(for summary: PassportSummary) -> some View {
        let count = min(mergedStamps(for: summary).count, 5)
        VStack(alignment: .leading, spacing: 12) {
            Text("Tier progress")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)

            // Track (background) + filled portion (foreground), with five
            // marker dots overlaid at the equal-width column centers.
            ZStack {
                GeometryReader { geo in
                    let pad = geo.size.width / 10  // half-column inset so
                                                   // the track spans dot 1
                                                   // through dot 5 only.
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(white: 0.18))
                            .frame(height: 3)
                        Capsule()
                            .fill(Brand.gold)
                            .frame(
                                width: max(0, (geo.size.width - 2 * pad) * CGFloat(max(0, count - 1)) / 4),
                                height: 3
                            )
                    }
                    .padding(.horizontal, pad)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 18)

                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { idx in
                        let filled = idx < count
                        Circle()
                            .fill(filled ? Brand.gold : Color(white: 0.22))
                            .overlay(
                                Circle()
                                    .stroke(filled ? Brand.gold : Color(white: 0.30), lineWidth: 2)
                            )
                            .frame(width: 16, height: 16)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { idx in
                    Text(progressAward(at: idx) ?? "")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(idx < count ? Brand.gold : .secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
        .cornerRadius(12)
    }

    /// Award label rendered under each milestone (only 3/4/5 have one).
    private func progressAward(at idx: Int) -> String? {
        switch idx {
        case 2: return "Gold"
        case 3: return "Black"
        case 4: return "Flight Suit"
        default: return nil
        }
    }

    /// Post-claim summary that replaces the tier card once the customer
    /// has hit "Claim card → Add to Wallet". Shows the day at a glance:
    /// start time, claim time, total duration, locations reached, and
    /// the card they walked away with.
    @ViewBuilder
    private func statsCard(for summary: PassportSummary) -> some View {
        let merged = mergedStamps(for: summary)
        let stampCount = merged.count
        // If the customer never pressed "Start the day" we still want a
        // meaningful duration — fall back to the first stamp as the
        // anchor and mark the row so they can tell it's inferred.
        let inferredStart = summary.passport.startedAt == nil
        let startAnchor = summary.passport.startedAt ?? merged.first?.checkedInAt
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Brand.gold)
                Text("Challenge complete")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
            }

            VStack(spacing: 0) {
                statRow(
                    label: inferredStart ? "Start (1st stamp)" : "Start",
                    value: timestampOrDash(startAnchor)
                )
                divider
                statRow(label: "Claim", value: timestampOrDash(summary.passport.completedAt))
                divider
                statRow(label: "Total duration", value: durationString(
                    from: startAnchor,
                    to: summary.passport.completedAt
                ))
                divider
                statRow(label: "Locations", value: "\(stampCount) / 5")
                divider
                statRow(label: "Card awarded", value: awardedDisplay(summary.passport.awardedTier))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10))
        .cornerRadius(12)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.18))
            .frame(height: 0.5)
    }

    private func timestampOrDash(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }

    private func durationString(from start: Date?, to end: Date?) -> String {
        guard let start, let end, end > start else { return "—" }
        let seconds = Int(end.timeIntervalSince(start))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    private func awardedDisplay(_ raw: String?) -> String {
        switch raw {
        case "gold":             return "Gold"
        case "gold_tattoo":      return "Black (via tattoo)"
        case "black":            return "Black"
        case "black_flightsuit": return "Black + Flight Suit"
        case .some(let s):       return s.capitalized
        case .none:              return "—"
        }
    }

    @ViewBuilder
    private func tierCard(for summary: PassportSummary) -> some View {
        let canClaim = summary.eligibleTier != .none && summary.passport.completedAt == nil
        Button(action: { if canClaim { isClaiming = true } }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.eligibleTier.displayName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                    if !summary.charlestonStamped {
                        Text("Charleston is required for any tier.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if canClaim {
                        Text("Tap to claim your card →")
                            .font(.footnote)
                            .foregroundColor(Brand.gold)
                    }
                    if let _ = summary.passport.completedAt, let awarded = summary.passport.awardedTier {
                        Text("Awarded: \(awarded)")
                            .font(.footnote)
                            .foregroundColor(Brand.gold)
                    }
                }
                Spacer()
                if canClaim {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Brand.gold)
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.10))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!canClaim)
    }

    @State private var startingDay = false

    /// Combined flights area: the live countdown to the next flight (only
    /// when one exists) plus a small "manage flights" affordance so the
    /// customer can add their itinerary if they haven't yet.
    @ViewBuilder
    private var flightStrip: some View {
        if flights.contains(where: { $0.departureAt > Date() }) {
            FlightCountdownView(flights: flights) {
                isManagingFlights = true
            }
        } else {
            Button(action: { isManagingFlights = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "airplane")
                        .foregroundColor(.secondary)
                    Text("Add your flights")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(white: 0.08))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    /// One-shot "I'm leaving home, the challenge begins now" button. Records
    /// the moment the customer hits the door; stays prominent until pressed
    /// so it's the obvious first action of the day. The button doesn't gate
    /// check-ins — if they forget, they can still stamp, but the stats card
    /// at the end will show "—" for total duration.
    private var startDayButton: some View {
        Button(action: startDay) {
            HStack(spacing: 10) {
                if startingDay {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.black)
                }
                Text(startingDay ? "Starting…" : "I'm leaving home — Start the day")
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.gold)
            .cornerRadius(12)
        }
        .disabled(startingDay)
    }

    /// On a new check-in, look back at any prior stamps where the customer
    /// never tapped "leaving" and fill in a best-guess `checkedOutAt`. The
    /// estimate is: scheduled departure of the flight from the prior city
    /// to the new city, minus 1h (airport buffer). If we can't find a
    /// matching flight, fall back to (new check-in time - 2.5h).
    ///
    /// The estimate is fired via the queue's checkout-edit kind and
    /// flagged in LocalStore.estimatedCheckouts so the cell renders a
    /// caution glyph; the user can re-tap the cell to nudge it.
    private func autoEstimatePreviousCheckout(newlyCheckedInAt: PendingCheckin) {
        guard let summary,
              let token = LocalStore.passportToken else { return }

        // Build the live picture of currently-stamped venues, so we can
        // find ones still open right when this new check-in lands.
        let merged = mergedStamps(for: summary)
        let openPriorStamps = merged.filter { stamp in
            stamp.venueId != newlyCheckedInAt.venueId
                && stamp.checkedOutAt == nil
                && stamp.checkedInAt < newlyCheckedInAt.observedAt
        }
        guard let mostRecent = openPriorStamps.max(by: { $0.checkedInAt < $1.checkedInAt }) else {
            return
        }

        let estimate = estimateCheckout(
            fromVenue: mostRecent.venueId,
            toVenue: newlyCheckedInAt.venueId,
            checkedInAt: mostRecent.checkedInAt,
            newCheckinAt: newlyCheckedInAt.observedAt
        )
        guard estimate > mostRecent.checkedInAt && estimate < newlyCheckedInAt.observedAt else {
            return
        }

        CheckinQueue.shared.enqueueCheckoutEdit(
            token: token,
            venueId: mostRecent.venueId,
            newCheckedOutAt: estimate
        )
        LocalStore.markCheckoutEstimated(mostRecent.venueId)
    }

    /// Flight-aware checkout estimator. Returns the best guess for when
    /// the customer left `fromVenue` given they've now checked in at
    /// `toVenue`. Pure function; safe to call regardless of network state.
    private func estimateCheckout(fromVenue: VenueId,
                                  toVenue: VenueId,
                                  checkedInAt: Date,
                                  newCheckinAt: Date) -> Date {
        let fromAirports = Set(fromVenue.airports)
        let toAirports = Set(toVenue.airports)
        // Find a flight whose route matches the leg AND whose departure
        // falls in the open window (after they checked in, before they
        // checked into the next city). 1h buffer subtracted as the rough
        // "got to the airport ahead of departure" margin. Airport-set
        // membership covers the multi-airport metros (NYC, Chicago) so
        // a JFK→ORD or LGA→MDW flight both match an NYC→Chicago leg.
        let matchingFlights = LocalStore.flights.filter { f in
            fromAirports.contains(f.originAirport)
                && toAirports.contains(f.destinationAirport)
                && f.departureAt > checkedInAt
                && f.departureAt < newCheckinAt
        }
        if let f = matchingFlights.min(by: { $0.departureAt < $1.departureAt }) {
            return f.departureAt.addingTimeInterval(-60 * 60)
        }
        // Fallback: 2.5h before the new check-in, clamped so we don't
        // estimate a time before the original check-in.
        let fallback = newCheckinAt.addingTimeInterval(-60 * 150)
        return max(fallback, checkedInAt.addingTimeInterval(60))
    }

    private func startDay() {
        guard let token = LocalStore.passportToken, !startingDay else { return }
        startingDay = true
        Task {
            _ = try? await APIClient.startPassport(token: token)
            startingDay = false
            await refresh()
        }
    }

    private var resetButton: some View {
        Button("Sign out (testing)") {
            if let token = LocalStore.passportToken {
                CheckinQueue.shared.clear(forToken: token)
            }
            LocalStore.clear()
            onReset()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func refresh() async {
        guard let token = LocalStore.passportToken else {
            errorMessage = "No passport token stored."
            loading = false
            return
        }
        loading = true
        errorMessage = nil
        do {
            summary = try await APIClient.passport(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
