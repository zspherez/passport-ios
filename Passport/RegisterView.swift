import SwiftUI

/// First-launch screen. Captures name + email + initial venue, calls
/// /passport/register, and stores the resulting passport token locally
/// so subsequent launches go straight to the passport view.
struct RegisterView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var venueId: VenueId = .nyc
    @State private var isSubmitting = false
    @State private var errorMessage: String?
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
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
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

    private var venuePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which venue are you at right now?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Venue", selection: $venueId) {
                ForEach(VenueId.allCases, id: \.self) { v in
                    Text(v.displayName).tag(v)
                }
            }
            .pickerStyle(.segmented)
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
        .disabled(isSubmitting || name.isEmpty || email.isEmpty || !acceptedTerms)
        .padding(.top, 8)
    }

    private var buttonLabel: String {
        switch submitStep {
        case .idle:        return "Start passport"
        case .locating:    return "Verifying location…"
        case .submitting:  return "Submitting…"
        }
    }

    @State private var submitStep: SubmitStep = .idle
    private enum SubmitStep { case idle, locating, submitting }

    private func submit() {
        errorMessage = nil
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
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    phone: phone.isEmpty ? nil : phone,
                    venueId: venueId,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
                let resp = try await APIClient.register(body)
                LocalStore.passportToken = resp.passportToken
                LocalStore.participantName = body.name
                LocalStore.participantEmail = body.email
                onRegistered()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RegisterView(onRegistered: {})
}
