import Foundation
import os

/// Swappable analytics sink. The app talks only to this protocol so a
/// Mixpanel/Amplitude client can be dropped in without touching call sites.
protocol AnalyticsClient {
    func track(_ event: AnalyticsEvent)
}

/// Every event the funnel math depends on. Keeping them in one enum means the
/// compiler enforces the taxonomy and the funnel (install → onboarding →
/// paywall → trial → paid) is computable from events alone.
enum AnalyticsEvent {
    case onboardingStarted
    case onboardingStepCompleted(step: String)
    case ratingPromptShown
    case profileGenerated(profile: String)
    case magicMomentCompleted
    case paywallShown(source: String)
    case trialStarted
    case purchaseCompleted(product: String)
    case paywallDismissAttempt
    case downsellShown
    case rollStarted(camera: String)
    case rollDeveloped
    case bulkDevelop(count: Int, camera: String)
    case photoSaved
    case photoShared(camera: String)
    case notificationPermission(granted: Bool)

    var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .onboardingStepCompleted: return "onboarding_step_completed"
        case .ratingPromptShown: return "rating_prompt_shown"
        case .profileGenerated: return "profile_generated"
        case .magicMomentCompleted: return "magic_moment_completed"
        case .paywallShown: return "paywall_shown"
        case .trialStarted: return "trial_started"
        case .purchaseCompleted: return "purchase_completed"
        case .paywallDismissAttempt: return "paywall_dismiss_attempt"
        case .downsellShown: return "downsell_shown"
        case .rollStarted: return "roll_started"
        case .rollDeveloped: return "roll_developed"
        case .bulkDevelop: return "bulk_develop"
        case .photoSaved: return "photo_saved"
        case .photoShared: return "photo_shared"
        case .notificationPermission: return "notification_permission"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .onboardingStepCompleted(let step): return ["step": step]
        case .profileGenerated(let profile): return ["profile": profile]
        case .paywallShown(let source): return ["source": source]
        case .purchaseCompleted(let product): return ["product": product]
        case .rollStarted(let camera): return ["camera": camera]
        case .bulkDevelop(let count, let camera): return ["count": count, "camera": camera]
        case .photoShared(let camera): return ["camera": camera]
        case .notificationPermission(let granted): return ["granted": granted]
        default: return [:]
        }
    }
}

/// Default sink: structured console logging so funnels are inspectable in
/// development before a real provider is wired up.
struct ConsoleAnalyticsClient: AnalyticsClient {
    private let logger = Logger(subsystem: AppConfig.bundleID, category: "analytics")

    func track(_ event: AnalyticsEvent) {
        let props = event.properties
        if props.isEmpty {
            logger.info("📊 \(event.name, privacy: .public)")
        } else {
            let rendered = props.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            logger.info("📊 \(event.name, privacy: .public) \(rendered, privacy: .public)")
        }
    }
}

/// Global access point. Swap `client` at launch to route events elsewhere.
enum Analytics {
    static var client: AnalyticsClient = ConsoleAnalyticsClient()
    static func track(_ event: AnalyticsEvent) { client.track(event) }
}
