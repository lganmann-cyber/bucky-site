import SwiftUI

/// The reusable hard paywall. From onboarding it's framed as activating the
/// user's Film Profile (their developed photo as hero, matched cameras
/// featured); from other sources it leads with the camera shelf.
/// No countdowns, no fake urgency — price, period, and renewal in plain text.
struct PaywallView: View {
    var source: String
    /// Onboarding context (nil when raised from locked camera / gates).
    var profileName: String? = nil
    var heroImage: UIImage? = nil
    var matchedCameras: [CameraID] = []
    var onPurchased: () -> Void = {}

    @ObservedObject private var gate = EntitlementGate.shared
    @State private var offering: PaywallOffering?
    @State private var selectedProductID = PaywallConfig.yearlyProductID
    @State private var purchasing = false
    @State private var errorText: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 40)
                }
                cameraShelf
                Text(PaywallConfig.priceAnchorLine)
                    .font(OSFont.body(14))
                    .foregroundStyle(OSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                planPicker
                if selectedProductID == PaywallConfig.weeklyProductID {
                    trialTimeline
                }
                purchaseButton
                if let errorText {
                    Text(errorText).font(OSFont.body(13)).foregroundStyle(.red)
                }
                legalRow
            }
            .padding(.vertical, 24)
        }
        .background(OSScreenBackground())
        .task { offering = await gate.service.offering(id: PaywallConfig.defaultOfferingID) }
        .onChange(of: scenePhase) { phase in
            // Backgrounding the app from a hard paywall counts as a leave attempt.
            if phase == .background { PaywallPresenter.shared.recordLeaveAttempt() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let profileName {
                OSDisplayText(text: "Start your \(profileName) setup.", size: 30)
            } else {
                OSDisplayText(text: "Open the full darkroom.", size: 30)
            }
            OSLabelText(text: "All 10 cameras · unlimited rolls · no watermarks", size: 11)
        }
        .padding(.horizontal, 24)
    }

    /// Matched cameras featured on top; the full shelf with locks below.
    private var cameraShelf: some View {
        VStack(spacing: 12) {
            if !matchedCameras.isEmpty {
                HStack(spacing: 10) {
                    ForEach(matchedCameras) { id in
                        let stock = FilmStockLibrary.stock(for: id)
                        VStack(spacing: 4) {
                            CameraBodyView(stock: stock)
                                .frame(width: 84, height: 58)
                            OSLabelText(text: stock.displayName, size: 10, color: OSColor.textPrimary)
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStockLibrary.all) { stock in
                        VStack(spacing: 3) {
                            CameraBodyView(stock: stock)
                                .frame(width: 62, height: 44)
                                .overlay(alignment: .topTrailing) {
                                    if !gate.isPro {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(OSColor.textSecondary)
                                            .padding(2)
                                    }
                                }
                            OSLabelText(text: stock.displayName, size: 8)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            planRow(productID: PaywallConfig.yearlyProductID,
                    title: "YEARLY",
                    price: livePrice(PaywallConfig.yearlyProductID) ?? PaywallConfig.yearlyPriceText,
                    badge: PaywallConfig.yearlyBadge,
                    detail: PaywallConfig.yearlyRenewalLine)
            planRow(productID: PaywallConfig.weeklyProductID,
                    title: "WEEKLY",
                    price: livePrice(PaywallConfig.weeklyProductID) ?? PaywallConfig.weeklyPriceText,
                    badge: "3-DAY FREE TRIAL",
                    detail: PaywallConfig.weeklyTrialLine)
        }
        .padding(.horizontal, 24)
    }

    private func livePrice(_ productID: String) -> String? {
        offering?.products.first { $0.id == productID }?.priceText
    }

    private func planRow(productID: String, title: String, price: String,
                         badge: String, detail: String) -> some View {
        let selected = selectedProductID == productID
        return Button {
            selectedProductID = productID
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(OSFont.display(18))
                    Spacer()
                    Text(price).font(OSFont.display(18))
                }
                OSLabelText(text: badge, size: 10, color: OSColor.accent)
                Text(detail).font(OSFont.body(12)).foregroundStyle(OSColor.textSecondary)
            }
            .foregroundStyle(OSColor.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? OSColor.field : OSColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? OSColor.accent : .clear, lineWidth: 2))
        }
        .accessibilityLabel("\(title), \(price). \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Today → Day 2 → Day 3, stated honestly.
    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PaywallConfig.trialTimeline, id: \.day) { item in
                HStack(alignment: .top, spacing: 10) {
                    OSLabelText(text: item.day, size: 11, color: OSColor.accent)
                        .frame(width: 52, alignment: .leading)
                    Text(item.text).font(OSFont.body(13)).foregroundStyle(OSColor.textPrimary)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private var purchaseButton: some View {
        OSPrimaryButton(title: purchasing ? "One moment…" : "Continue", enabled: !purchasing) {
            purchase()
        }
        .padding(.horizontal, 24)
    }

    private func purchase() {
        guard let product = offering?.products.first(where: { $0.id == selectedProductID })
            ?? offering?.products.first else { return }
        purchasing = true
        errorText = nil
        Task {
            do {
                let active = try await gate.service.purchase(product)
                gate.setPro(active)
                if active { onPurchased() }
            } catch {
                errorText = "Purchase didn't complete. You have not been charged."
            }
            purchasing = false
        }
    }

    private var legalRow: some View {
        HStack(spacing: 18) {
            Button("Restore Purchases") { restore() }
            Link("Terms", destination: AppConfig.termsURL)
            Link("Privacy", destination: AppConfig.privacyURL)
        }
        .font(OSFont.body(12))
        .foregroundStyle(OSColor.textSecondary)
    }

    private func restore() {
        Task {
            let active = (try? await gate.service.restore()) ?? false
            gate.setPro(active)
            if active { onPurchased() }
            else { errorText = "No previous purchase found for this Apple ID." }
        }
    }
}

// MARK: - Downsell

/// One-time offer shown on launch after repeated paywall exits. Lifetime,
/// once, forever — no clock, no pressure.
struct DownsellView: View {
    var onFinished: () -> Void

    @ObservedObject private var gate = EntitlementGate.shared
    @State private var offering: PaywallOffering?
    @State private var purchasing = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            OSLabelText(text: PaywallConfig.downsellHeadline, size: 12, color: OSColor.accent)
            OSDisplayText(text: "The darkroom, forever.", size: 30)
            Text(PaywallConfig.downsellBody)
                .font(OSFont.body(15))
                .foregroundStyle(OSColor.textSecondary)
                .multilineTextAlignment(.center)
            OSDisplayText(text: livePrice ?? PaywallConfig.lifetimePriceText, size: 40, color: OSColor.accent)
            OSLabelText(text: "One payment · lifetime access · all future cameras", size: 11)
            Spacer()
            OSPrimaryButton(title: purchasing ? "One moment…" : "Get lifetime access",
                            enabled: !purchasing) { purchase() }
            Button("No thanks") { onFinished() }
                .font(OSFont.label(13))
                .foregroundStyle(OSColor.textSecondary)
                .padding(.bottom, 16)
        }
        .padding(24)
        .background(OSScreenBackground())
        .task { offering = await gate.service.offering(id: PaywallConfig.downsellOfferingID) }
    }

    private var livePrice: String? {
        offering?.products.first?.priceText
    }

    private func purchase() {
        guard let product = offering?.products.first else { return }
        purchasing = true
        Task {
            let active = (try? await gate.service.purchase(product)) ?? false
            gate.setPro(active)
            purchasing = false
            if active { onFinished() }
        }
    }
}

// MARK: - Lapsed banner

/// Persistent, polite. Shown only in the lapsed free-tier state.
struct LapsedBanner: View {
    var body: some View {
        Button {
            PaywallPresenter.shared.present(source: "lapsed_banner")
        } label: {
            HStack {
                Image(systemName: "key.fill").font(.system(size: 12))
                Text(PaywallConfig.lapsedBannerText)
                    .font(OSFont.label(14))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11))
            }
            .foregroundStyle(OSColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(OSColor.surface)
        }
        .accessibilityLabel("Restore full darkroom")
    }
}
