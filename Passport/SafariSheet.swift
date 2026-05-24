import SafariServices
import SwiftUI

/// SFSafariViewController wrapper for in-app web sessions. Used so the
/// wallet install link (returned by /signup/request) opens inside the
/// passport app instead of punting out to Safari. SFSafariViewController
/// is Safari under the hood, so taps on "Add to Apple Wallet" still
/// trigger the system pass-install handoff exactly like Safari does.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Tiny Identifiable URL wrapper so we can present SafariSheet via
/// `.sheet(item:)` without lifting URL into a custom protocol elsewhere.
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
