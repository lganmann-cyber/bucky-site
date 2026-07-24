import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = RollStore.shared
    @EnvironmentObject private var gate: EntitlementGate

    @State private var storageBytes: Int64 = 0
    @State private var showClearConfirm = false
    @State private var restoreResult: String?

    var body: some View {
        List {
            Section("Membership") {
                if gate.isPro {
                    Label("OldSnap Pro active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(OSColor.ink)
                } else {
                    Button("Unlock all cameras") {
                        PaywallPresenter.shared.present(source: "settings")
                    }
                }
                Button("Restore Purchases") { restore() }
                if let restoreResult {
                    Text(restoreResult).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                LabeledContent("Space used",
                               value: ByteCountFormatter.string(fromByteCount: storageBytes,
                                                                countStyle: .file))
                Button("Clear cached originals") { showClearConfirm = true }
                Text("Removes sandbox copies of photos that can be re-fetched from your photo library. Developed prints are never touched.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                Link("Terms of Service", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
                LabeledContent("Version", value: Bundle.main.osVersionText)
            }

            #if OLDSNAP_DEBUG_TOOLS
            Section("Developer") {
                NavigationLink("Preset comparison grid") { PresetComparisonView() }
                Button("Reset onboarding") {
                    UserDefaults.standard.set(false, forKey: "os.onboarding.done")
                }
                Button("Toggle mock Pro") {
                    let key = "os.mock.pro"
                    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
                    Task { await gate.refresh() }
                }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(OSColor.cream)
        .navigationTitle("Settings")
        .onAppear { storageBytes = store.storageBytesUsed() }
        .confirmationDialog("Clear cached originals?", isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                store.clearRefetchableOriginals()
                storageBytes = store.storageBytesUsed()
            }
        }
    }

    private func restore() {
        Task {
            let active = (try? await gate.service.restore()) ?? false
            gate.setPro(active)
            restoreResult = active ? "Purchases restored." : "No previous purchase found."
        }
    }
}

extension Bundle {
    var osVersionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
