import SwiftUI

/// Pre-event signup screen. Captures name + email + the venue the
/// customer plans to start at on challenge day. No location check here —
/// the first stamp lands when they actually arrive at a venue and tap
/// the cell. The token + cached name/email persist in LocalStore so
/// subsequent launches go straight to the passport view.
struct RegisterView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var venueId: VenueId = .nyc
    @State private var isSubmitting = false
    @State private var failure: RegisterFailure?
    @State private var acceptedTerms: Bool = false
    /// Drives the in-app SFSafariViewController sheet for the T&C link.
    @State private var termsSheet: IdentifiableURL?

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
                    field(title: "Legal name", text: $name, contentType: .name)
                    field(title: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    field(title: "Phone (optional)", text: $phone, contentType: .telephoneNumber, keyboard: .phonePad)
                    venuePicker
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
        .sheet(item: $termsSheet) { wrapped in
            SafariSheet(url: wrapped.url)
                .ignoresSafeArea()
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
                Text("Set up your passport")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(2)
            }
            Text("Register before May 9. On the day, tap \u{201C}I\u{2019}m starting the day\u{201D} to begin your run — your first stamp lands when you arrive at your first venue. Charleston is required; visit three or more for the entry tier.")
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

    private var venuePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where are you planning to start?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Venue", selection: $venueId) {
                ForEach(VenueId.allCases, id: \.self) { v in
                    Text(v.displayName).tag(v)
                }
            }
            .pickerStyle(.segmented)
            Text("Just a hint for the day — your first actual stamp can be at any venue.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack {
                if isSubmitting { ProgressView().tint(.black) }
                Text(isSubmitting ? "Submitting…" : "Save my passport")
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Brand.gold)
            .cornerRadius(12)
        }
        .disabled(isSubmitting || name.isEmpty || email.isEmpty || !acceptedTerms)
        .padding(.top, 8)
    }

    /// Banner shown above the submit button after a failed attempt. One row
    /// per case — icon, headline, supporting copy. Same chrome for all
    /// failures so the user reads the same shape every time.
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

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !isPlausibleEmail(trimmedEmail) {
            failure = .invalidEmail
            return
        }

        failure = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let body = RegisterRequest(
                    name: trimmedName,
                    email: trimmedEmail,
                    phone: phone.isEmpty ? nil : phone,
                    venueId: venueId
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
    /// Client-side email format check failed before we hit the network.
    case invalidEmail
    /// Backend returned a per-field validation error (zod flatten result).
    case validation(field: String, message: String)
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
        case .invalidEmail:   return "envelope.badge.shield.half.filled"
        case .validation:     return "exclamationmark.bubble"
        case .unknown:        return "exclamationmark.circle"
        }
    }

    var title: String {
        switch self {
        case .network:                   return "Can't reach the server"
        case .invalidEmail:              return "That email doesn't look right"
        case .validation(let field, _): return "Check your \(field)"
        case .unknown:                   return "Something went wrong"
        }
    }

    var body: String {
        switch self {
        case .network:
            return "Check your connection and try again."
        case .invalidEmail:
            return "Double-check the address — we need a valid one to send your wallet card."
        case .validation(_, let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}

#Preview {
    RegisterView(onRegistered: {})
}
