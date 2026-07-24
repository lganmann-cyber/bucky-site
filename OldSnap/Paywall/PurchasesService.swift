import Foundation
import Combine

#if canImport(RevenueCat)
import RevenueCat
#endif

/// One product as the paywall renders it — abstracted so the UI never touches
/// RevenueCat types directly.
struct PaywallProduct: Identifiable {
    let id: String            // product ID
    let title: String
    let priceText: String
    let detailText: String
    let hasTrial: Bool
    #if canImport(RevenueCat)
    var package: Package? = nil
    #endif
}

struct PaywallOffering {
    var products: [PaywallProduct]
}

/// Purchase abstraction: RevenueCat in production, an instant mock in
/// dev/simulator so the whole funnel is testable without StoreKit.
protocol PurchasesService: AnyObject {
    func configure()
    /// True when the `pro` entitlement is currently active.
    func refreshEntitlement() async -> Bool
    func offering(id: String) async -> PaywallOffering?
    /// Returns the active entitlement state after the purchase.
    func purchase(_ product: PaywallProduct) async throws -> Bool
    func restore() async throws -> Bool
}

// MARK: - RevenueCat implementation

#if canImport(RevenueCat)
final class RevenueCatPurchases: PurchasesService {
    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: AppConfig.revenueCatAPIKey)
    }

    func refreshEntitlement() async -> Bool {
        guard let info = try? await Purchases.shared.customerInfo() else { return false }
        return info.entitlements[PaywallConfig.entitlementID]?.isActive == true
    }

    func offering(id: String) async -> PaywallOffering? {
        guard let offerings = try? await Purchases.shared.offerings(),
              let offering = offerings.offering(identifier: id) ?? offerings.current
        else { return nil }
        let products = offering.availablePackages.map { package -> PaywallProduct in
            let product = package.storeProduct
            let hasTrial = product.introductoryDiscount?.paymentMode == .freeTrial
            return PaywallProduct(
                id: product.productIdentifier,
                title: product.localizedTitle,
                priceText: product.localizedPriceString,
                detailText: product.localizedDescription,
                hasTrial: hasTrial,
                package: package)
        }
        return PaywallOffering(products: products)
    }

    func purchase(_ product: PaywallProduct) async throws -> Bool {
        guard let package = product.package else { return false }
        let result = try await Purchases.shared.purchase(package: package)
        let active = result.customerInfo.entitlements[PaywallConfig.entitlementID]?.isActive == true
        if active {
            if product.hasTrial { Analytics.track(.trialStarted) }
            Analytics.track(.purchaseCompleted(product: product.id))
        }
        return active
    }

    func restore() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        return info.entitlements[PaywallConfig.entitlementID]?.isActive == true
    }
}
#endif

// MARK: - Mock (dev builds / RevenueCat unavailable)

final class MockPurchases: PurchasesService {
    private let key = "os.mock.pro"

    func configure() {}

    func refreshEntitlement() async -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    func offering(id: String) async -> PaywallOffering? {
        if id == PaywallConfig.downsellOfferingID {
            return PaywallOffering(products: [
                PaywallProduct(id: PaywallConfig.lifetimeProductID, title: "Lifetime",
                               priceText: PaywallConfig.lifetimePriceText,
                               detailText: PaywallConfig.downsellBody, hasTrial: false),
            ])
        }
        return PaywallOffering(products: [
            PaywallProduct(id: PaywallConfig.yearlyProductID, title: "Yearly",
                           priceText: PaywallConfig.yearlyPriceText,
                           detailText: PaywallConfig.yearlyRenewalLine, hasTrial: false),
            PaywallProduct(id: PaywallConfig.weeklyProductID, title: "Weekly",
                           priceText: PaywallConfig.weeklyPriceText,
                           detailText: PaywallConfig.weeklyTrialLine, hasTrial: true),
        ])
    }

    func purchase(_ product: PaywallProduct) async throws -> Bool {
        try await Task.sleep(nanoseconds: 600_000_000)
        UserDefaults.standard.set(true, forKey: key)
        if product.hasTrial { Analytics.track(.trialStarted) }
        Analytics.track(.purchaseCompleted(product: product.id))
        return true
    }

    func restore() async throws -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Entitlement gate

/// The single yes/no authority for locked features: locked cameras, bulk
/// develops beyond the free limit, and watermark removal all ask here.
@MainActor
final class EntitlementGate: ObservableObject {
    static let shared = EntitlementGate()

    @Published private(set) var isPro = false
    /// True once a user has ever held the entitlement — distinguishes a
    /// lapsed subscriber (free-tier state) from a never-purchased user
    /// (hard-paywalled onboarding).
    @Published private(set) var hasEverBeenPro = false

    let service: PurchasesService

    private let everProKey = "os.everPro"

    private init() {
        #if canImport(RevenueCat)
        // Placeholder key → mock, so dev builds work before RC is configured.
        if AppConfig.revenueCatAPIKey.contains("PLACEHOLDER") {
            service = MockPurchases()
        } else {
            service = RevenueCatPurchases()
        }
        #else
        service = MockPurchases()
        #endif
        hasEverBeenPro = UserDefaults.standard.bool(forKey: everProKey)
    }

    func start() {
        service.configure()
        Task { await refresh() }
    }

    func refresh() async {
        let active = await service.refreshEntitlement()
        setPro(active)
    }

    func setPro(_ active: Bool) {
        isPro = active
        if active {
            hasEverBeenPro = true
            UserDefaults.standard.set(true, forKey: everProKey)
        }
    }

    /// Lapsed users keep the free-tier cameras (watermarked); active pros get
    /// everything.
    func canUse(camera: CameraID) -> Bool {
        isPro || AppConfig.freeTierCameraIDs.contains(camera.rawValue)
    }

    func canUseWithoutWatermark(camera: CameraID) -> Bool {
        isPro
    }

    /// Free-tier lapsed state applies only after an entitlement existed.
    var isLapsed: Bool { hasEverBeenPro && !isPro }
}

// MARK: - Paywall presentation

/// Central presenter so any surface (locked camera tap, bulk gate, lapsed
/// banner, onboarding) can raise the same paywall with a `source` for
/// analytics. Also owns the one-time downsell trigger.
@MainActor
final class PaywallPresenter: ObservableObject {
    static let shared = PaywallPresenter()

    @Published var presentedSource: String?
    @Published var showDownsell = false

    private let leaveAttemptsKey = "os.paywall.leaveAttempts"
    private let downsellShownKey = "os.paywall.downsellShown"

    func present(source: String) {
        presentedSource = source
        Analytics.track(.paywallShown(source: source))
    }

    /// Called when the user tries to leave a hard paywall (background or
    /// repeated dismiss attempts).
    func recordLeaveAttempt() {
        Analytics.track(.paywallDismissAttempt)
        let count = UserDefaults.standard.integer(forKey: leaveAttemptsKey) + 1
        UserDefaults.standard.set(count, forKey: leaveAttemptsKey)
    }

    /// One-time downsell on next launch after ≥2 leave attempts, never again.
    func maybeShowDownsellOnLaunch(isPro: Bool) {
        guard !isPro,
              UserDefaults.standard.integer(forKey: leaveAttemptsKey) >= 2,
              !UserDefaults.standard.bool(forKey: downsellShownKey) else { return }
        UserDefaults.standard.set(true, forKey: downsellShownKey)
        showDownsell = true
        Analytics.track(.downsellShown)
    }
}
