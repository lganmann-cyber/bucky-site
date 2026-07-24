import SwiftUI

@main
struct OldSnapApp: App {
    @StateObject private var gate = EntitlementGate.shared
    @StateObject private var paywall = PaywallPresenter.shared

    init() {
        EntitlementGate.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gate)
                .environmentObject(paywall)
                .tint(OSColor.accent)
        }
    }
}

/// Routes between onboarding and the main app, and hosts the globally
/// presented paywall + one-time downsell.
struct RootView: View {
    @EnvironmentObject private var gate: EntitlementGate
    @EnvironmentObject private var paywall: PaywallPresenter

    @AppStorage("os.onboarding.done") private var onboardingDone = false
    @AppStorage("os.camera.selected") private var selectedCameraRaw = CameraID.c35.rawValue
    @State private var tab: Tab = .camera

    enum Tab { case camera, library, develop, settings }

    var body: some View {
        Group {
            if onboardingDone {
                mainApp
            } else {
                OnboardingFlow { profile in
                    // Land in the live camera with the profile's primary
                    // camera loaded; the one-time coach overlay takes it from there.
                    if let profile {
                        selectedCameraRaw = profile.primaryCamera.rawValue
                    }
                    onboardingDone = true
                    tab = .camera
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { paywall.presentedSource != nil },
            set: { shown in
                if !shown {
                    paywall.presentedSource = nil
                    // Dismissing without buying counts toward the downsell.
                    if !gate.isPro { paywall.recordLeaveAttempt() }
                }
            })) {
            PaywallView(source: paywall.presentedSource ?? "unknown") {
                paywall.presentedSource = nil
            }
        }
        .fullScreenCover(isPresented: $paywall.showDownsell) {
            DownsellView { paywall.showDownsell = false }
        }
        .onAppear {
            if onboardingDone {
                paywall.maybeShowDownsellOnLaunch(isPro: gate.isPro)
            }
        }
    }

    private var mainApp: some View {
        VStack(spacing: 0) {
            if gate.isLapsed { LapsedBanner() }
            TabView(selection: $tab) {
                CameraView()
                    .tabItem { Label("Camera", systemImage: "camera.fill") }
                    .tag(Tab.camera)
                NavigationStack { LibraryView() }
                    .tabItem { Label("Rolls", systemImage: "film.stack") }
                    .tag(Tab.library)
                DevelopTabView()
                    .tabItem { Label("Develop", systemImage: "tray.and.arrow.down.fill") }
                    .tag(Tab.develop)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
        }
    }
}

/// The develop tab is just an entry point that raises the import flow.
struct DevelopTabView: View {
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40))
                .foregroundStyle(OSColor.accent)
            OSDisplayText(text: "Develop from camera roll", size: 26)
            Text("Pick up to \(AppConfig.rollCapacity) photos — one roll — and run them through any camera.")
                .font(OSFont.body(15))
                .foregroundStyle(OSColor.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            OSPrimaryButton(title: "Choose photos") { showImport = true }
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OSColor.cream)
        .fullScreenCover(isPresented: $showImport) {
            ImportFlowView()
        }
    }
}
