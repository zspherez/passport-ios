import Foundation

/// Backend hosts the app talks to. Values are injected at build time from
/// `Configuration/Debug.xcconfig` / `Configuration/Release.xcconfig` into
/// Info.plist and read back here.
///
/// We keep scheme and host as separate keys (`APIBaseScheme` + `APIBaseHost`)
/// rather than a single full URL because xcconfig parses `//` as a comment
/// marker — splitting at the protocol-separator lets us avoid every escape
/// trick. To point either build at a different host, edit the xcconfig
/// file for that configuration and rebuild.
enum Config {
    /// Passport backend (this app's own DB of participants + stamps).
    static let apiBaseURL: String = url(scheme: "APIBaseScheme", host: "APIBaseHost")

    /// Wallet-card backend. Where claiming a card after completing the
    /// challenge posts to so the customer gets their install link emailed
    /// + an immediate Add-to-Wallet URL.
    static let walletApiBaseURL: String = url(scheme: "WalletAPIBaseScheme", host: "WalletAPIBaseHost")

    private static func url(scheme schemeKey: String, host hostKey: String) -> String {
        "\(infoString(schemeKey))://\(infoString(hostKey))"
    }

    private static func infoString(_ key: String) -> String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.hasPrefix("$(")
        else {
            fatalError("""
                Missing Info.plist value for \(key). Make sure \
                Configuration/Debug.xcconfig and Release.xcconfig set \
                API_BASE_SCHEME / API_BASE_HOST / WALLET_API_BASE_SCHEME / \
                WALLET_API_BASE_HOST, and that project.yml wires them \
                through Info.plist. Regenerate with `xcodegen`.
                """)
        }
        return value
    }
}
