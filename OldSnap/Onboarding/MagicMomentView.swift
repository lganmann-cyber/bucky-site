import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// The reciprocity beat: the user develops ONE of their own photos in their
/// profile's primary camera, presented as a print with the profile name
/// stamped beneath. Theirs to save, watermark-free, before any paywall.
struct MagicMomentView: View {
    let profile: FilmProfile
    /// Called with the developed image when the user continues.
    let onContinue: (UIImage?) -> Void

    private enum Stage {
        case prime          // purpose screen before the permission/picker
        case picking
        case developing
        case reveal
    }

    @State private var stage: Stage = .prime
    @State private var developed: UIImage?
    @State private var animPhase: Double = 0
    @State private var saved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch stage {
        case .prime: prime
        case .picking:
            PhotoPicker(maxSelection: 1) { results in
                handlePicked(results)
            } onCancel: {
                stage = .prime
            }
            .ignoresSafeArea()
        case .developing: developingView
        case .reveal: reveal
        }
    }

    // MARK: - Permission prime

    private var prime: some View {
        VStack(spacing: 20) {
            Spacer()
            OSDisplayText(text: "Let's develop your first print.", size: 30)
                .padding(.horizontal, 32)
            Text("Pick one photo — any photo. We'll develop it through your \(FilmStockLibrary.stock(for: profile.primaryCamera).displayName). Limited photo access is completely fine.")
                .font(OSFont.body(15))
                .foregroundStyle(OSColor.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            OSPrimaryButton(title: "Choose a photo") { stage = .picking }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Develop

    private func handlePicked(_ results: [PHPickerResult]) {
        guard let result = results.first else { stage = .prime; return }
        stage = .developing
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { stage = .prime }
                return
            }
            let stock = FilmStockLibrary.stock(for: profile.primaryCamera)
            let options = FilmEngine.RenderOptions(
                seed: SeededRandom.freshSeed(), quality: .full,
                dateStamp: stock.dateStampDefault ? .retroRandom : .off,
                watermark: false) // theirs, free, always
            let rendered = FilmEngine.shared.developUIImage(source: image, stock: stock, options: options)
            DispatchQueue.main.async {
                developed = rendered
                stage = .reveal
                if reduceMotion {
                    animPhase = 1
                } else {
                    withAnimation(.easeInOut(duration: 2.2)) { animPhase = 1 }
                }
            }
        }
    }

    private var developingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(OSColor.accent)
            OSLabelText(text: "In the developer bath…", size: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reveal

    private var reveal: some View {
        VStack(spacing: 18) {
            Spacer()
            if let developed {
                VStack(spacing: 12) {
                    Image(uiImage: developed)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 400)
                        .opacity(0.2 + 0.8 * animPhase)
                        .saturation(animPhase)
                    OSDisplayText(text: profile.id, size: 20, color: OSColor.accent)
                }
                .padding(16)
                .background(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 10) {
                OSSecondaryButton(title: saved ? "Saved ✓" : "Save to Photos") { save() }
                OSPrimaryButton(title: "Continue") { onContinue(developed) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func save() {
        guard let developed, let data = developed.jpegData(compressionQuality: 0.95) else { return }
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }) { success, _ in
            DispatchQueue.main.async {
                if success {
                    saved = true
                    Analytics.track(.photoSaved)
                }
            }
        }
    }
}
