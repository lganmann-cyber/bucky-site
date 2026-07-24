import Foundation

/// Central switchboard for identifiers, keys, and tunables that change
/// between environments or need fast iteration without hunting through code.
enum AppConfig {
    /// Swappable bundle identifier (mirrors PRODUCT_BUNDLE_IDENTIFIER in the project).
    static let bundleID = "com.timberline.oldsnap"

    /// RevenueCat public SDK key. Placeholder — replace before shipping.
    static let revenueCatAPIKey = "REVENUECAT_PUBLIC_API_KEY_PLACEHOLDER"

    /// Social proof figure shown in onboarding. Update as real numbers exist —
    /// never fabricate a specific number. `nil` hides the count entirely and
    /// the screen falls back to qualitative copy only.
    static let socialProofCount: Int? = nil

    /// Seconds a live-shot roll spends "in the lab" before its frames develop.
    static let rollDevelopSeconds: TimeInterval = 30

    /// Maximum photos in one roll / one bulk develop batch.
    static let rollCapacity = 36

    /// Free tier: bulk develops larger than this require the pro entitlement.
    static let freeBulkDevelopLimit = 5

    /// Cameras that stay usable (watermarked) when a trial lapses.
    static let freeTierCameraIDs: Set<String> = [CameraID.c35.rawValue, CameraID.mono400.rawValue]

    static let termsURL = URL(string: "https://oldsnap.app/terms")!
    static let privacyURL = URL(string: "https://oldsnap.app/privacy")!

    /// True when the debug tooling (preset comparison grid, mock purchases)
    /// should be reachable. Never true in App Store builds.
    static var debugToolsEnabled: Bool {
        #if OLDSNAP_DEBUG_TOOLS
        return true
        #else
        return false
        #endif
    }
}
