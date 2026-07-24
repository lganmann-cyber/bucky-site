import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// "Develop from Camera Roll": single and bulk (up to 36 = one roll).
/// Flow: pick → choose camera (or Shuffle) → lab-order progress → review.
struct ImportFlowView: View {
    @StateObject private var coordinator = ImportCoordinator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.stage {
                case .picking:
                    PhotoPicker(maxSelection: AppConfig.rollCapacity) { results in
                        coordinator.handlePicked(results)
                    } onCancel: {
                        dismiss()
                    }
                    .ignoresSafeArea()
                case .chooseCamera:
                    CameraChoiceView(coordinator: coordinator)
                case .importing, .developing:
                    LabOrderProgressView(coordinator: coordinator)
                case .singleDevelop(let rollID, let shot):
                    DevelopAnimationView(rollID: rollID, shot: shot) {
                        coordinator.stage = .review(rollID: rollID)
                    }
                case .review(let rollID):
                    BulkReviewView(rollID: rollID) { dismiss() }
                }
            }
            .background(OSColor.cream)
        }
        .interactiveDismissDisabled(coordinator.isWorking)
    }
}

// MARK: - Coordinator

@MainActor
final class ImportCoordinator: ObservableObject {
    enum Stage: Equatable {
        case picking
        case chooseCamera
        case importing
        case developing
        case singleDevelop(rollID: UUID, shot: Shot)
        case review(rollID: UUID)
    }

    @Published var stage: Stage = .picking
    @Published var progressText = ""
    @Published var progress: Double = 0

    private var picked: [PHPickerResult] = []
    private var rollID: UUID?

    var isWorking: Bool {
        stage == .importing || stage == .developing
    }

    func handlePicked(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { stage = .picking; return }
        picked = Array(results.prefix(AppConfig.rollCapacity))
        stage = .chooseCamera
    }

    var pickedCount: Int { picked.count }

    /// camera == nil means Shuffle: era-appropriate random assignment per photo.
    func startDevelop(camera: CameraID?) {
        // Free tier gates bulk develops beyond the small-batch limit.
        if picked.count > AppConfig.freeBulkDevelopLimit,
           !EntitlementGate.shared.isPro {
            PaywallPresenter.shared.present(source: "bulk_develop_gate")
            return
        }
        if let camera, !EntitlementGate.shared.canUse(camera: camera) {
            PaywallPresenter.shared.present(source: "locked_camera_import")
            return
        }
        stage = .importing
        let results = picked
        Task { await runImport(results: results, camera: camera) }
    }

    /// Copies originals into the sandbox one at a time (never the whole batch
    /// in memory), builds the roll, then hands off to the render queue.
    private func runImport(results: [PHPickerResult], camera: CameraID?) async {
        let store = RollStore.shared
        let newRollID = UUID()
        rollID = newRollID
        var shots: [Shot] = []
        var shuffler = SeededRandom(seed: SeededRandom.freshSeed())

        for (index, result) in results.enumerated() {
            progressText = "Loading \(index + 1) of \(results.count)…"
            progress = Double(index) / Double(results.count)

            let data: Data? = await withCheckedContinuation { continuation in
                guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                    continuation.resume(returning: nil); return
                }
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data, let image = UIImage(data: data) else { continue }

            // Re-encode oriented JPEG so the pipeline sees upright pixels;
            // EXIF for export is preserved from this sandbox copy.
            let jpeg: Data? = autoreleasepool {
                image.osNormalizedUp()?.jpegData(compressionQuality: 0.95)
            }
            guard let jpeg else { continue }

            let assignedCamera = camera ?? Self.shuffleCamera(using: &shuffler)
            let shot = Shot(id: UUID(), cameraID: assignedCamera, seed: SeededRandom.freshSeed(),
                            capturedAt: Date(), sourceAssetIdentifier: result.assetIdentifier,
                            stampMode: .off)
            let url = store.originalURL(roll: newRollID, shot: shot.id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            do {
                try jpeg.write(to: url, options: .atomic)
                shots.append(shot)
            } catch { continue }
        }

        guard !shots.isEmpty else { stage = .picking; return }

        var roll = Roll(id: newRollID, cameraID: camera, createdAt: Date(),
                        source: .imported, shots: shots, state: .developing(endsAt: Date()))
        store.update(roll)
        Analytics.track(.bulkDevelop(count: shots.count,
                                     camera: camera?.rawValue ?? "shuffle"))

        if shots.count == 1, let only = shots.first {
            // Single photo: render now, then play the full develop animation.
            stage = .developing
            progressText = "Developing…"
            await DevelopQueue().renderNow(
                rollID: newRollID, shot: only, store: store,
                watermark: !EntitlementGate.shared.canUseWithoutWatermark(camera: only.cameraID))
            roll.state = .developed
            roll.shots[0].isDeveloped = true
            store.update(roll)
            stage = .singleDevelop(rollID: newRollID, shot: only)
            return
        }

        stage = .developing
        await observeQueue(rollID: newRollID, store: store, total: shots.count)
    }

    /// Watches store progress while the shared queue renders the batch.
    private func observeQueue(rollID: UUID, store: RollStore, total: Int) async {
        // Kick the renders through the store so kill/relaunch resumes them.
        if var roll = store.roll(rollID) {
            roll.state = .developing(endsAt: Date())
            store.update(roll)
            store.finishDevelopingIfReady(rollID: rollID)
        }
        await DevelopQueue().enqueue(rollID: rollID,
                                     shots: store.roll(rollID)?.shots.filter { !$0.isDeveloped } ?? [],
                                     store: store)
        if var roll = store.roll(rollID) {
            roll.state = .developed
            store.update(roll)
        }
        stage = .review(rollID: rollID)
    }

    /// Shuffle weights: the viral, broadly-flattering looks lead; specialist
    /// formats (diptych, instant) appear but stay rare.
    static func shuffleCamera(using rng: inout SeededRandom) -> CameraID {
        let weighted: [(CameraID, Double)] = [
            (.c35, 0.22), (.sun200, 0.20), (.dc2000, 0.16), (.t800, 0.10),
            (.chrome64, 0.10), (.mono400, 0.08), (.l79, 0.06), (.p110, 0.05),
            (.sq70, 0.03),
        ]
        let total = weighted.reduce(0) { $0 + $1.1 }
        var draw = rng.unit() * total
        for (camera, weight) in weighted {
            draw -= weight
            if draw <= 0 { return camera }
        }
        return .c35
    }
}

// MARK: - Camera choice

struct CameraChoiceView: View {
    @ObservedObject var coordinator: ImportCoordinator

    var body: some View {
        VStack(spacing: 20) {
            OSDisplayText(text: "\(coordinator.pickedCount) photo\(coordinator.pickedCount == 1 ? "" : "s") on the bench", size: 26)
            OSLabelText(text: "Choose a camera for this roll", size: 12)

            ScrollView {
                VStack(spacing: 10) {
                    OSChoiceRow(title: "SHUFFLE",
                                subtitle: "We assign an era-appropriate camera to each photo.") {
                        coordinator.startDevelop(camera: nil)
                    }
                    ForEach(FilmStockLibrary.all) { stock in
                        let locked = !EntitlementGate.shared.canUse(camera: stock.id)
                        OSChoiceRow(title: locked ? "\(stock.displayName)  🔒" : stock.displayName,
                                    subtitle: "\(stock.eraTag) · \(stock.tagline)") {
                            coordinator.startDevelop(camera: stock.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
    }
}

// MARK: - Lab-order progress

struct LabOrderProgressView: View {
    @ObservedObject var coordinator: ImportCoordinator
    @ObservedObject private var store = RollStore.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(OSColor.accent)
            OSDisplayText(text: "Lab order in progress", size: 24)
            Text(progressLine)
                .font(OSFont.stamp(16))
                .foregroundStyle(OSColor.ink)
            ProgressView(value: progressValue)
                .tint(OSColor.accent)
                .padding(.horizontal, 60)
            Text("Keep the app open for fastest developing — your order is safe either way.")
                .font(OSFont.body(13))
                .foregroundStyle(OSColor.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var progressLine: String {
        if case .developing = coordinator.stage,
           let (done, total) = store.developProgress.values.first {
            return "Developing \(min(done + 1, total)) of \(total)…"
        }
        return coordinator.progressText
    }

    private var progressValue: Double {
        if let (done, total) = store.developProgress.values.first, total > 0 {
            return Double(done) / Double(total)
        }
        return coordinator.progress
    }
}

// MARK: - PHPicker bridge

struct PhotoPicker: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPicked: ([PHPickerResult]) -> Void
    var onCancel: (() -> Void)?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = maxSelection
        config.selection = .ordered
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                parent.onCancel?()
            } else {
                parent.onPicked(results)
            }
        }
    }
}
