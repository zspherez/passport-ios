import SwiftUI
import UIKit

/// Native rendition of the wallet backend's signup form. Surfaces when the
/// participant has earned at least Gold (3 stops incl. Charleston). On
/// submit, hits mothers/backend's POST /signup/request and opens the
/// returned install URL externally so Safari can hand off to Apple Wallet.
struct ClaimCardView: View {
    /// Eligible tier from the passport summary — drives the cardType options.
    let eligibleTier: EligibleTier
    /// Number of venues the participant has stamped (3/4/5).
    let locationsVisited: Int
    /// Defaults pulled from LocalStore so the customer doesn't retype.
    let initialName: String
    let initialEmail: String
    /// Suggest the participant's registration venue as the default home city.
    let initialHomeCity: HomeCity?

    let onDismiss: () -> Void

    @State private var displayName: String = ""
    @State private var cardChoice: CardChoice = .gold
    @State private var homeCitySelection: HomeCity = .nyc
    @State private var homeCityOther: String = ""
    @State private var priorYears: Set<Int> = []
    @State private var isRepeatOffender: Bool = false
    /// On by default when the customer has flights in LocalStore — the
    /// implication being that if they bothered adding them, they want
    /// the trip on record. Server-side persistence is a follow-up; for v1
    /// the checkbox is captured in the request body and ignored upstream.
    @State private var submitFlights: Bool = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Code word staff types in / says aloud after verifying the tattoo.
    /// Only required when `cardChoice == .black` (the tattoo-path).
    @State private var staffCodeWord: String = ""
    /// In-app Safari sheet driven by the install URL returned from the
    /// wallet backend. Presented over this form so the user stays inside
    /// the passport app for the entire claim → install flow.
    @State private var installSheet: IdentifiableURL?

    /// Has to match the value staff hands out. Local-only check; the server
    /// neither knows nor enforces this (acceptable since the next bartender
    /// + photo ID at redemption is the real gate against fake claims).
    private static let tattooCodeWord = "legend"

    /// Local choice that maps to the wallet's "cardType" string. For Gold
    /// eligibility the customer can opt into Black via the tattoo path; for
    /// Black/Black-flightsuit eligibility we force Black.
    ///
    /// In repeat-offender mode the question shifts from "what did you earn
    /// this year?" to "what's the highest tier you've ever received?", so
    /// we collapse the subtypes — `.gold`/`.black` are the only choices and
    /// their display labels simplify accordingly. The server still receives
    /// `cardType` either way; it just promotes it to `highestTier` and sets
    /// the row's effective cardType to `"repeat"` when priors are present.
    enum CardChoice: String, CaseIterable, Hashable {
        case gold = "Gold (1 free beer/day)"
        case black = "Black w/ tattoo (1 free cocktail/day)"
        case blackFour = "Black (4 stops, no tattoo needed)"
        case blackFlightsuit = "Black + Flight Suit (all 5 stops)"

        var apiValue: String {
            switch self {
            case .gold: return "gold"
            case .black, .blackFour, .blackFlightsuit: return "black"
            }
        }

        /// Tier string the passport backend recognizes for closeout. Gold
        /// "with tattoo" (the .black choice on a 3-stop run) collapses to a
        /// distinct `gold_tattoo` tier so the passport history captures the
        /// upgrade path without inflating it to a true 4-stop Black.
        var passportAwardedTier: String {
            switch self {
            case .gold:            return "gold"
            case .black:           return "gold_tattoo"
            case .blackFour:       return "black"
            case .blackFlightsuit: return "black_flightsuit"
            }
        }

        /// The text shown in the picker. For repeat offenders, drop the
        /// stops/tattoo qualifiers since the choice is about historical
        /// tier, not this year's earn path.
        func displayLabel(repeatOffender: Bool) -> String {
            if repeatOffender {
                return apiValue == "black" ? "Black card" : "Gold card"
            }
            return rawValue
        }
    }

    /// Derived from the current calendar year — matches `priorYearsList()` in
    /// mothers/backend's `routes/signup.ts`, which also enumerates 2023 up to
    /// (but excluding) this year.
    private static var priorYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(2023..<currentYear)
    }

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nameField
                    emailDisplay
                    homeCityPicker
                    // Repeat-offender block comes BEFORE the card picker so
                    // the picker's question + options can pivot based on
                    // repeat state (highest-tier-ever vs. this-year-earned).
                    // Matches the layout of mothers/backend's signup.ts HTML.
                    repeatToggle
                    cardPicker
                    tattooCodeField
                    flightsCheckbox
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    submitButton
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: setupDefaults)
        .onChange(of: isRepeatOffender) { _ in
            // Flipping repeat-mode can shrink availableCardChoices (e.g.
            // dropping `.blackFour`/`.blackFlightsuit`); snap selection to
            // the first valid option so the checkmark doesn't disappear.
            if !availableCardChoices.contains(cardChoice) {
                cardChoice = availableCardChoices.first ?? .gold
            }
        }
        .sheet(item: $installSheet, onDismiss: onDismiss) { wrapped in
            SafariSheet(url: wrapped.url)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claim your card")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Brand.gold)
                Spacer()
                Button("Close", action: onDismiss)
                    .foregroundColor(.secondary)
            }
            Text(eligibleTier.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)
            Text("Walk this through with the manager at your final stop. The card hits your wallet right after you submit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Display name (for the pass)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("First name or nickname", text: $displayName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color(white: 0.16))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }

    private var emailDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Email")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(initialEmail)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.10))
                .cornerRadius(8)
                .foregroundStyle(.secondary)
        }
    }

    private var cardPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isRepeatOffender
                 ? "Which is the highest tier card you have received?"
                 : "Which card did you earn?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(availableCardChoices, id: \.self) { choice in
                Button(action: { cardChoice = choice }) {
                    HStack {
                        Text(choice.displayLabel(repeatOffender: isRepeatOffender))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        if cardChoice == choice {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Brand.gold)
                        }
                    }
                    .padding(12)
                    .background(Color(white: cardChoice == choice ? 0.16 : 0.10))
                    .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder
    private var tattooCodeField: some View {
        if requiresTattooCode {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tattoo verification code")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Ask the staff member to verify the tattoo and give you the code word.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Code word from staff", text: $staffCodeWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                if !staffCodeWord.isEmpty && !tattooCodeValid {
                    Text("That doesn't match — check with staff.")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var homeCityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home city")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Home city", selection: $homeCitySelection) {
                ForEach(HomeCity.allCases, id: \.self) { c in
                    Text(c == .other ? "Other" : c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(Brand.gold)
            .padding(12)
            .background(Color(white: 0.16))
            .cornerRadius(8)

            if homeCitySelection == .other {
                TextField("Type your city", text: $homeCityOther)
                    .padding(12)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
    }

    private var repeatToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isRepeatOffender) {
                Text("I'm a repeat offender")
                    .foregroundColor(.white)
            }
            .tint(Brand.gold)

            if isRepeatOffender {
                Text("Which prior years did you complete?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(Self.priorYearOptions, id: \.self) { y in
                    Toggle(String(y), isOn: priorYearBinding(for: y))
                        .tint(Brand.gold)
                        .foregroundColor(.white)
                }
            }
        }
    }

    /// Only shown when the customer has added flights to the app. Lets
    /// them opt into bundling the trip itinerary with the wallet claim so
    /// staff (eventually) has a record of how they flew the challenge.
    @ViewBuilder
    private var flightsCheckbox: some View {
        let storedFlights = LocalStore.flights
        if !storedFlights.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Button(action: { submitFlights.toggle() }) {
                    Image(systemName: submitFlights ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(submitFlights ? Brand.gold : .secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Submit my flight itinerary (\(storedFlights.count) flight\(storedFlights.count == 1 ? "" : "s"))")
                        .font(.footnote)
                        .foregroundColor(.white)
                    Text("So staff knows how you pulled this off.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack {
                if isSubmitting { ProgressView().tint(.black) }
                Text(isSubmitting ? "Submitting…" : "Claim card → Add to Wallet")
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Brand.gold)
            .cornerRadius(12)
        }
        .disabled(!canSubmit)
        .padding(.top, 8)
    }

    // MARK: - State helpers

    private var requiresTattooCode: Bool {
        // The tattoo path is the gold→black UPGRADE for this year's earn:
        // 3 stops + verified tattoo = Black. A repeat offender's `.black`
        // choice is about their HISTORICAL highest tier (no fresh tattoo
        // proof needed at this redemption), so the code-word gate doesn't
        // apply.
        cardChoice == .black && !isRepeatOffender
    }

    private var tattooCodeValid: Bool {
        staffCodeWord
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            == Self.tattooCodeWord
    }

    private var canSubmit: Bool {
        guard !isSubmitting,
              !displayName.isEmpty,
              !resolvedHomeCity.isEmpty
        else { return false }
        if requiresTattooCode && !tattooCodeValid { return false }
        return true
    }

    private var availableCardChoices: [CardChoice] {
        // Repeat offenders are picking their HISTORICAL highest tier, not
        // this year's earn path — so the stops/tattoo/flight-suit qualifiers
        // don't apply. Mirror the web form: just Black or Gold.
        if isRepeatOffender {
            return [.gold, .black]
        }
        switch eligibleTier {
        case .none, .gold:
            return [.gold, .black]
        case .black:
            return [.blackFour]
        case .blackFlightsuit:
            return [.blackFlightsuit]
        }
    }

    private func priorYearBinding(for year: Int) -> Binding<Bool> {
        Binding(
            get: { priorYears.contains(year) },
            set: { included in
                if included { priorYears.insert(year) }
                else        { priorYears.remove(year) }
            }
        )
    }

    private var resolvedHomeCity: String {
        homeCitySelection == .other
            ? homeCityOther.trimmingCharacters(in: .whitespaces)
            : homeCitySelection.rawValue
    }

    private func setupDefaults() {
        if displayName.isEmpty {
            displayName = initialName.split(separator: " ").first.map(String.init) ?? initialName
        }
        if let initialHomeCity {
            homeCitySelection = initialHomeCity
        }
        cardChoice = availableCardChoices.first ?? .gold
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        let body = WalletSignupRequest(
            name: initialName,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            email: initialEmail,
            homeCity: resolvedHomeCity,
            cardType: cardChoice.apiValue,
            locationsVisited: locationsVisited,
            priorYears: Array(priorYears).sorted()
        )
        let awardedTier = cardChoice.passportAwardedTier
        let flightsToSubmit: [Flight] = submitFlights ? LocalStore.flights : []
        Task {
            do {
                let resp = try await APIClient.claimWalletCard(body)
                // Close out the passport side too so `awardedTier` /
                // `completedAt` reflect the wallet claim without a staff
                // member firing the admin endpoint. Fire-and-forget: if it
                // fails we still want the user to install their wallet pass,
                // and staff can manually close out from /admin/passports.
                // Same idea for the optional flight-history upload: a
                // failed POST shouldn't block the customer from installing
                // their wallet pass.
                if let token = LocalStore.passportToken {
                    Task.detached {
                        _ = try? await APIClient.completePassport(token: token, awardedTier: awardedTier)
                        if !flightsToSubmit.isEmpty {
                            _ = try? await APIClient.uploadFlights(token: token, flights: flightsToSubmit)
                        }
                    }
                }
                isSubmitting = false
                if let urlStr = resp.installUrl, let url = URL(string: urlStr) {
                    // Present the install page inside the app via
                    // SFSafariViewController. The SafariSheet's onDismiss
                    // (wired in body) calls onDismiss after the user closes
                    // it, so the customer stays in Passport for the whole
                    // claim → Add-to-Wallet flow.
                    installSheet = IdentifiableURL(url: url)
                } else {
                    errorMessage = resp.message ?? "Submitted, but no install link came back."
                }
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension HomeCity {
    /// Map a VenueId to the matching preset HomeCity so we can suggest one.
    static func fromVenue(_ venueId: VenueId) -> HomeCity {
        switch venueId {
        case .nyc: return .nyc
        case .chi: return .chicago
        case .nas: return .nashville
        case .aus: return .austin
        case .cha: return .charleston
        }
    }
}
