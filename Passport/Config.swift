import Foundation

/// Backend hosts the app talks to. Values are injected at build time from
/// `Configuration/Debug.xcconfig` / `Configuration/Release.xcconfig` into
/// Info.plist (`APIBaseURL`, `WalletAPIBaseURL`) and read back here. To
/// point either build at a different host, edit the xcconfig file for
/// that configuration and rebuild.
enum Config {
    /// Passport backend (this app's own DB of participants + stamps).
    static let apiBaseURL: String = infoString("APIBaseURL")

    /// Wallet-card backend. Where claiming a card after completing the
    /// challenge posts to so the customer gets their install link emailed
    /// + an immediate Add-to-Wallet URL.
    static let walletApiBaseURL: String = infoString("WalletAPIBaseURL")

    private static func infoString(_ key: String) -> String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.hasPrefix("$(")
        else {
            fatalError("""
                Missing Info.plist value for \(key). Make sure \
                Configuration/Debug.xcconfig and Release.xcconfig set \
                API_BASE_URL and WALLET_API_BASE_URL, and that project.yml \
                wires them through Info.plist. Regenerate with `xcodegen`.
                """)
        }
        return value
    }
}
