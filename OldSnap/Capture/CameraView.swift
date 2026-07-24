import SwiftUI
import AVKit

/// The live camera: a full-screen skeuomorphic body whose viewfinder shows
/// the selected film look in real time. Shots land in the active roll as
/// undeveloped frames — a wind-on animation plays and the photo stays hidden
/// until the roll develops.
struct CameraView: View {
    @StateObject private var controller = CameraController()
    @ObservedObject private var store = RollStore.shared
    @ObservedObject private var gate = EntitlementGate.shared

    @AppStorage("os.camera.selected") private var selectedCameraRaw = CameraID.c35.rawValue
    @AppStorage("os.camera.coachShown") private var coachShown = false

    @State private var windOn = false
    @State private var ejecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedCamera: CameraID {
        CameraID(rawValue: selectedCameraRaw) ?? .c35
    }
    private var stock: FilmStock { FilmStockLibrary.stock(for: selectedCamera) }

    var body: some View {
        ZStack {
            Color(hex: stock.bodyStyle.bodyHex).ignoresSafeArea()

            VStack(spacing: 0) {
                topControls
                viewfinder
                bottomDeck
            }

            if let count = controller.countdown {
                Text("\(count)")
                    .font(OSFont.stamp(90))
                    .foregroundStyle(OSColor.textPrimary)
                    .transition(.opacity)
            }

            if ejecting { ejectOverlay }
            if !coachShown && gate.isPro { coachOverlay }
        }
        .background(volumeShutter)
        .onAppear {
            controller.activeStock = stock
            controller.onCapture = handleCapture
            controller.start()
        }
        .onDisappear { controller.stop() }
        .onChange(of: selectedCameraRaw) { _ in
            controller.activeStock = stock
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let frame = controller.previewFrame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if !controller.isAuthorized {
                VStack(spacing: 10) {
                    Text("OldSnap needs the camera to shoot film.")
                        .font(OSFont.body(15))
                        .foregroundStyle(OSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    OSSecondaryButton(title: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .frame(width: 180)
                }
                .padding()
            }

            // Wind-on: a dark sweep after each shot instead of a photo preview.
            if windOn {
                Rectangle().fill(Color.black)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
        .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 3))
        .padding(.horizontal, 22)
        .accessibilityLabel("Viewfinder, \(stock.displayName) look")
    }

    // MARK: - Controls

    private var topControls: some View {
        HStack(spacing: 22) {
            if hasFlash {
                controlButton(icon: controller.flashOn ? "bolt.fill" : "bolt.slash",
                              label: "Flash") {
                    controller.flashOn.toggle()
                }
            }
            controlButton(icon: "timer", label: controller.timerSeconds == 0 ? "Timer off" : "Timer \(controller.timerSeconds)s") {
                controller.timerSeconds = controller.timerSeconds == 0 ? 3
                    : controller.timerSeconds == 3 ? 10 : 0
            }
            .overlay(alignment: .topTrailing) {
                if controller.timerSeconds > 0 {
                    Text("\(controller.timerSeconds)")
                        .font(OSFont.stamp(10))
                        .foregroundStyle(OSColor.stampOrange)
                }
            }
            controlButton(icon: "arrow.triangle.2.circlepath.camera", label: "Flip camera") {
                controller.flipCamera()
            }
            Spacer()
            rollCounter
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OSColor.textPrimary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.black.opacity(0.3)))
        }
        .accessibilityLabel(label)
    }

    /// Mechanical frame counter: shots used on the active roll.
    private var rollCounter: some View {
        let used = store.activeRoll?.shots.count ?? 0
        return VStack(spacing: 1) {
            Text(String(format: "%02d", used))
                .font(OSFont.stamp(18))
                .foregroundStyle(OSColor.stampOrange)
            OSLabelText(text: "of \(AppConfig.rollCapacity)", size: 8, color: OSColor.textPrimary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.5)))
        .accessibilityLabel("\(used) of \(AppConfig.rollCapacity) exposures used")
    }

    // MARK: - Bottom deck: shutter + shelf

    private var bottomDeck: some View {
        VStack(spacing: 14) {
            HStack {
                if let roll = store.activeRoll, !roll.shots.isEmpty {
                    Button {
                        store.sendToLab(rollID: roll.id)
                    } label: {
                        OSLabelText(text: "End roll → lab", size: 11, color: OSColor.textPrimary.opacity(0.8))
                    }
                    .accessibilityLabel("End roll and send to lab")
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            shutterButton
            cameraShelf
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var shutterButton: some View {
        Button {
            guard gate.canUse(camera: selectedCamera) else {
                PaywallPresenter.shared.present(source: "locked_camera_shutter")
                return
            }
            controller.triggerShutter()
        } label: {
            Circle()
                .fill(Color(hex: stock.bodyStyle.accentHex))
                .frame(width: 74, height: 74)
                .overlay(Circle().stroke(OSColor.textPrimary.opacity(0.7), lineWidth: 3).padding(5))
        }
        .accessibilityLabel("Shutter")
    }

    /// Horizontal shelf of rendered camera bodies. Locked cameras carry a
    /// padlock and raise the paywall.
    private var cameraShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilmStockLibrary.all) { candidate in
                    let locked = !gate.canUse(camera: candidate.id)
                    Button {
                        if locked {
                            PaywallPresenter.shared.present(source: "locked_camera_shelf")
                        } else {
                            selectedCameraRaw = candidate.id.rawValue
                        }
                    } label: {
                        VStack(spacing: 4) {
                            CameraBodyView(stock: candidate)
                                .frame(width: 88, height: 60)
                                .overlay(alignment: .topTrailing) {
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(OSColor.textPrimary)
                                            .padding(3)
                                            .background(Color.black.opacity(0.5))
                                    }
                                }
                                .overlay(
                                    Rectangle().stroke(
                                        candidate.id == selectedCamera ? OSColor.accent : .clear,
                                        lineWidth: 2))
                            OSLabelText(text: "\(candidate.displayName) · \(candidate.eraTag)",
                                        size: 8, color: OSColor.textPrimary.opacity(0.75))
                        }
                    }
                    .accessibilityLabel("\(candidate.displayName), \(candidate.eraTag)\(locked ? ", locked" : "")")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Capture handling

    private func handleCapture(_ data: Data) {
        guard let image = UIImage(data: data),
              let jpeg = image.osNormalizedUp()?.jpegData(compressionQuality: 0.95) else { return }
        let roll = store.ensureActiveRoll(camera: selectedCamera)
        store.addShot(toRoll: roll.id, cameraID: selectedCamera, originalJPEG: jpeg,
                      stampMode: stock.dateStampDefault ? .retroRandom : .off)

        if selectedCamera == .sq70 {
            runEject()
        } else {
            runWindOn()
        }
    }

    private func runWindOn() {
        SoundHaptics.shared.windOn()
        if reduceMotion {
            return // cut: no sweep, counter just ticks
        }
        withAnimation(.easeIn(duration: 0.12)) { windOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.25)) { windOn = false }
        }
    }

    private func runEject() {
        if reduceMotion { return }
        ejecting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { ejecting = false }
    }

    /// SQ-70: a blank print slides out of the slot. It stays blank —
    /// development happens in the lab like everything else.
    private var ejectOverlay: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(hex: 0xEFEAE0))
                .frame(width: 190, height: 230)
                .overlay(
                    Rectangle().fill(Color(hex: 0x22201C))
                        .padding(EdgeInsets(top: 12, leading: 12, bottom: 46, trailing: 12)))
                .transition(.move(edge: .bottom))
                .osAnimation(.easeOut(duration: 1.2), value: ejecting)
                .padding(.bottom, 130)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coach overlay (one-time, post-purchase)

    private var coachOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                OSDisplayText(text: "Shoot your first roll", size: 20, color: OSColor.textPrimary)
                Text("36 exposures, then it goes to the lab. No previews — that's the point.")
                    .font(OSFont.body(13))
                    .foregroundStyle(OSColor.textPrimary.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button("Got it") { coachShown = true }
                    .font(OSFont.label(14))
                    .foregroundStyle(OSColor.accent)
                    .padding(.top, 4)
            }
            .padding(20)
            .background(Color.black.opacity(0.82))
            .padding(.horizontal, 40)
            .padding(.bottom, 220)
        }
    }

    private var hasFlash: Bool {
        [.c35, .dc2000, .l79, .sun200].contains(selectedCamera)
    }

    /// Hardware shutter via capture events (iOS 17.2+); earlier systems just
    /// don't get volume capture.
    @ViewBuilder
    private var volumeShutter: some View {
        if #available(iOS 17.2, *) {
            VolumeShutterHost {
                controller.triggerShutter()
            }
            .frame(width: 0, height: 0)
        }
    }
}

@available(iOS 17.2, *)
private struct VolumeShutterHost: UIViewRepresentable {
    let onTrigger: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let interaction = AVCaptureEventInteraction { event in
            if event.phase == .ended { onTrigger() }
        }
        view.addInteraction(interaction)
        interaction.isEnabled = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
