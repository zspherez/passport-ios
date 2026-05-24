import SwiftUI

/// First-launch screen. Captures name + email + the venue QR the customer
/// is standing in front of, calls /passport/register, and stores the
/// returned passport token locally so subsequent launches go straight to
/// the passport view. Two ways to get the venue QR onto the form:
///   1. Universal Link from the system camera lands directly here with
///      `scannedQR` pre-filled (see DeepLinkRouter).
///   2. Tap "Scan venue QR" inside the form to open the in-app scanner.
/// Either way the venue + token are locked once captured — the registration
/// request can't proceed without them.
struct RegisterView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var scannedQR: ScannedVenueQR?
    @State private var isSubmitting = false
    @State private var showingScanner = false
    @State private var failure: RegisterFailure?
    @State private var acceptedTerms: Bool = false
    /// Drives the in-app SFSafariViewController sheet for the T&C link.
    @State private var termsSheet: IdentifiableURL?
    @EnvironmentObject private var deepLinks: DeepLinkRouter

    /// Where "terms and conditions in DocuSign" navigates. Placeholder until
    /// the real DocuSign URL is provisioned.
    private static let termsURL = URL(string: "https://docusign.com")!

    let onRegistered: () -> Void

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    venueScanCard
                    field(title: "Legal name", text: $name, contentType: .name)
                    field(title: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    field(title: "Phone (optional)", text: $phone, contentType: .telephoneNumber, keyboard: .phonePad)
                    termsCheckbox
                    if let failure {
                        failureCallout(failure)
                    }
                    submitButton
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { consumeDeepLinkIfPresent() }
        .onChange(of: deepLinks.pendingScan) { _ in consumeDeepLinkIfPresent() }
        .sheet(item: $termsSheet) { wrapped in
            SafariSheet(url: wrapped.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView(
                onScan: { payload in
                    showingScanner = false
                    handleScannedPayload(payload)
                },
                onCancel: { showingScanner = false }
            )
            .ignoresSafeArea()
        }
    }

    /// Replaces the old segmented venue picker. Pre-scan: a single CTA to
    /// open the scanner. Post-scan: confirmation of which venue is locked
    /// in, with a "Re-scan" link in case they tapped the wrong QR.
    private var venueScanCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Venue")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let scanned = scannedQR {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Brand.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scanned.venueId.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Venue QR verified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Re-scan") { showingScanner = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Brand.gold)
                }
                .padding(12)
                .background(Color(red: 0.16, green: 0.16, blue: 0.17))
                .cornerRadius(8)
            } else {
                Button(action: { showingScanner = true }) {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan venue QR")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundColor(Brand.gold)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Brand.gold.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Required acknowledgement. Checkbox plus tappable text — the link
    /// opens in an in-app SFSafariViewController so the user stays in the
    /// passport app while reviewing terms.
    private var termsCheckbox: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: { acceptedTerms.toggle() }) {
                Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(acceptedTerms ? Brand.gold : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(acceptedTerms ? "Terms accepted" : "Accept terms")

            let attributed: AttributedString = {
                let markdown = "I have signed the [terms and conditions in DocuSign](https://docusign.com) (REQUIRED)"
                let style = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                return (try? AttributedString(markdown: markdown, options: style)) ?? AttributedString(markdown)
            }()

            Text(attributed)
                .font(.footnote)
                .foregroundColor(.white)
                .tint(Brand.gold)
                .multilineTextAlignment(.leading)
                .environment(\.openURL, OpenURLAction { _ in
                    termsSheet = IdentifiableURL(url: Self.termsURL)
                    return .handled
                })
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180)
                .padding(.top, 4)
            VStack(spacing: 2) {
                Text("Mother's Day Challenge")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Brand.gold)
                Text("Start your passport")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(2)
            }
            Text("You'll get a stamp at each Mother's Ruin you visit on May 9. Charleston is required; pick at least two more.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func field(title: String,
                       text: Binding<String>,
                       contentType: UITextContentType,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .padding(12)
                .background(Color(red: 0.16, green: 0.16, blue: 0.17))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack {
                if isSubmitting { ProgressView().tint(.black) }
                Text(buttonLabel)
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Brand.gold)
            .cornerRadius(12)
        }
        .disabled(isSubmitting || name.isEmpty || email.isEmpty || !acceptedTerms || scannedQR == nil)
        .padding(.top, 8)
    }

    private var buttonLabel: String {
        switch submitStep {
        case .idle:        return scannedQR == nil ? "Scan venue QR to begin" : "Start passport"
        case .locating:    return "Verifying location…"
        case .submitting:  return "Submitting…"
        }
    }

    @State private var submitStep: SubmitStep = .idle
    private enum SubmitStep { case idle, locating, submitting }

    /// Banner shown above the submit button after a failed attempt. One row
    /// per case — icon, headline, supporting copy.
    private func failureCallout(_ failure: RegisterFailure) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failure.icon)
                .font(.title3)
                .foregroundColor(.red)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(failure.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                Text(failure.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }

    private func consumeDeepLinkIfPresent() {
        if let scan = deepLinks.consume() {
            scannedQR = scan
        }
    }

    private func handleScannedPayload(_ payload: String) {
        guard let scan = DeepLink.parseVenueQR(from: payload) else {
            failure = .invalidQR
            return
        }
        scannedQR = scan
        // Clear any prior "scan the QR first" prompt or unrelated error.
        if failure == .invalidQR || failure == .missingQR {
            failure = nil
        }
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let scan = scannedQR else {
            failure = .missingQR
            return
        }
        if !isPlausibleEmail(trimmedEmail) {
            failure = .invalidEmail
            return
        }

        failure = nil
        isSubmitting = true
        submitStep = .locating
        Task {
            defer {
                isSubmitting = false
                submitStep = .idle
            }
            do {
                let loc = try await LocationManager.shared.oneShot()
                submitStep = .submitting
                let body = RegisterRequest(
                    name: trimmedName,
                    email: trimmedEmail,
                    phone: phone.isEmpty ? nil : phone,
                    venueId: scan.venueId,
                    venueQrToken: scan.qrToken,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
                let resp = try await APIClient.register(body)
                LocalStore.passportToken = resp.passportToken
                LocalStore.participantName = body.name
                LocalStore.participantEmail = body.email
                onRegistered()
            } catch {
                failure = RegisterFailure(error: error)
            }
        }
    }

    /// Cheap "looks like an email" check so we don't make the user wait for
    /// a network round-trip on a typo. Backend still has the authoritative
    /// `z.string().email()` gate.
    private func isPlausibleEmail(_ s: String) -> Bool {
        guard let at = s.firstIndex(of: "@"), at != s.startIndex else { return false }
        let domain = s[s.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !domain.hasPrefix(".")
    }
}

/// Closed set of registration failure modes. Each case carries enough
/// context to render a tailored message — generic "request failed" copy
/// is a last resort.
private enum RegisterFailure: Equatable {
    /// Couldn't reach the server at all (no network, DNS fail, timeout).
    case network
    /// User is outside the venue's geofence. Server's message already
    /// names the venue and reports the distance, so we just relay it.
    case tooFar(message: String)
    /// User hit submit without scanning a venue QR first.
    case missingQR
    /// Scanned a QR but it didn't decode to a known venue.
    case invalidQR
    /// Client-side email format check failed before we hit the network.
    case invalidEmail
    /// Backend returned a per-field validation error (zod flatten result).
    case validation(field: String, message: String)
    /// Server says the QR secret doesn't match — likely a stale or wrong QR.
    case wrongVenueQR
    /// Anything else — backend 5xx, unknown 4xx, decoding failure.
    case unknown(message: String)

    init(error: Error) {
        guard let apiError = error as? APIError else {
            self = .unknown(message: error.localizedDescription)
            return
        }
        switch apiError {
        case .network:
            self = .network
        case .invalidURL, .invalidResponse:
            self = .unknown(message: apiError.errorDescription ?? "Unexpected response from the server.")
        case .server(let message):
            self = Self.classify(serverMessage: message)
        }
    }

    private static func classify(serverMessage message: String) -> RegisterFailure {
        if message.hasPrefix("Too far") {
            return .tooFar(message: message)
        }
        if message.contains("Venue QR") {
            return .wrongVenueQR
        }
        // `humanReadableError` formats zod field errors as "field: message".
        if let colon = message.firstIndex(of: ":") {
            let field = String(message[..<colon])
            let rest = message[message.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !field.isEmpty && !rest.isEmpty && !field.contains(" ") {
                return .validation(field: field, message: rest)
            }
        }
        return .unknown(message: message)
    }

    var icon: String {
        switch self {
        case .network:        return "wifi.slash"
        case .tooFar:         return "location.slash"
        case .missingQR:      return "qrcode.viewfinder"
        case .invalidQR:      return "exclamationmark.triangle"
        case .invalidEmail:   return "envelope.badge.shield.half.filled"
        case .validation:     return "exclamationmark.bubble"
        case .wrongVenueQR:   return "qrcode"
        case .unknown:        return "exclamationmark.circle"
        }
    }

    var title: String {
        switch self {
        case .network:                   return "Can't reach the server"
        case .tooFar:                    return "You're not at the venue"
        case .missingQR:                 return "Scan the venue QR first"
        case .invalidQR:                 return "That isn't a venue QR"
        case .invalidEmail:              return "That email doesn't look right"
        case .validation(let field, _): return "Check your \(field)"
        case .wrongVenueQR:              return "Wrong venue QR"
        case .unknown:                   return "Something went wrong"
        }
    }

    var body: String {
        switch self {
        case .network:
            return "Check your connection and try again."
        case .tooFar(let message):
            return message + ". Make sure Location is set to \"While Using the App\" and you're inside the bar."
        case .missingQR:
            return "Tap \"Scan venue QR\" and point your camera at the printed QR on the bar."
        case .invalidQR:
            return "That QR code didn't look like a Mother's Ruin venue QR. Try the printed one on the bar."
        case .invalidEmail:
            return "Double-check the address — we need a valid one to send your wallet card."
        case .validation(_, let message):
            return message
        case .wrongVenueQR:
            return "The scanned QR doesn't match this venue's current secret. Ask staff to confirm the QR isn't an old printout."
        case .unknown(let message):
            return message
        }
    }
}

#Preview {
    RegisterView(onRegistered: {})
        .environmentObject(DeepLinkRouter.shared)
}
