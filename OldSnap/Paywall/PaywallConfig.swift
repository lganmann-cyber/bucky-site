import Foundation

/// Every price, product ID, and line of paywall copy in one place for fast
/// iteration. Display prices are fallbacks — live StoreKit prices from
/// RevenueCat always win when available.
enum PaywallConfig {
    // MARK: Products (must match App Store Connect / RevenueCat)
    static let yearlyProductID = "os_yearly_3499"
    static let weeklyProductID = "os_weekly_499"
    static let lifetimeProductID = "os_lifetime_6999"
    static let yearlyIntroProductID = "os_yearly_intro_2499"

    static let entitlementID = "pro"
    static let defaultOfferingID = "default"
    static let downsellOfferingID = "downsell"

    // MARK: Fallback display pricing
    static let yearlyPriceText = "$34.99/yr"
    static let yearlyPerWeekText = "$0.67/wk"
    static let weeklyPriceText = "$4.99/wk"
    static let lifetimePriceText = "$69.99"

    // MARK: Copy — all App Review 3.1.2-plain: price, period, renewal stated.
    static let priceAnchorLine = "One roll of real film, developed: ~$25. OldSnap: every camera, unlimited rolls."
    static let yearlyBadge = "BEST VALUE · \(yearlyPerWeekText)"
    static let weeklyTrialLine = "Free for 3 days, then $4.99/week. Cancel anytime in Settings."
    static let yearlyRenewalLine = "$34.99/year, renews annually. Cancel anytime in Settings."
    static let downsellHeadline = "One-time offer"
    static let downsellBody = "The full darkroom, once, forever. No subscription."
    static let lapsedBannerText = "Restore full darkroom"

    /// Honest weekly-trial timeline — no countdowns, no fake urgency.
    static let trialTimeline: [(day: String, text: String)] = [
        ("Today", "Every camera unlocked. Shoot and develop freely."),
        ("Day 2", "We remind you the trial is ending."),
        ("Day 3", "Billed $4.99/week unless cancelled."),
    ]
}
