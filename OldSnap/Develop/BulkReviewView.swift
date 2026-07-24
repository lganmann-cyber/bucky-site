import SwiftUI
import Photos

/// Post-develop review: contact sheet of the roll → tap into a detail card
/// with press-and-hold before/after and per-photo actions (re-roll variation,
/// switch camera, remove) → "Save roll" exports the kept photos in one pass.
struct BulkReviewView: View {
    @ObservedObject private var store = RollStore.shared
    let rollID: UUID
    let onDone: () -> Void

    @State private var selected: Set<UUID> = []
    @State private var detailShot: Shot?
    @State private var saving = false
    @State private var savedCount: Int?

    private var roll: Roll? { store.roll(rollID) }
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 4)]

    var body: some View {
        VStack(spacing: 0) {
            if let roll {
                header(roll)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(roll.shots) { shot in
                            cell(shot: shot)
                        }
                    }
                    .padding(12)
                }
                footer
            }
        }
        .background(OSColor.cream)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let roll { selected = Set(roll.shots.map(\.id)) }
        }
        .sheet(item: $detailShot) { shot in
            ReviewDetailSheet(rollID: rollID, shotID: shot.id)
        }
        .alert("Saved \(savedCount ?? 0) photos", isPresented: Binding(
            get: { savedCount != nil }, set: { if !$0 { savedCount = nil; onDone() } })) {
            Button("Done", role: .cancel) {}
        }
    }

    private func header(_ roll: Roll) -> some View {
        VStack(spacing: 4) {
            OSDisplayText(text: "Contact sheet", size: 24)
            OSLabelText(text: "\(roll.shots.count) exposures · \(roll.displayCameraName)", size: 11)
            OSLabelText(text: "Tap a frame to inspect · selected frames save", size: 10)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func cell(shot: Shot) -> some View {
        let isSelected = selected.contains(shot.id)
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = store.developedImage(roll: rollID, shot: shot.id) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(hex: 0x14130F))
                        .overlay(ProgressView().tint(.white))
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .opacity(isSelected ? 1 : 0.35)

            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? OSColor.accent : OSColor.cream)
                .padding(4)
        }
        .onTapGesture { detailShot = shot }
        .onLongPressGesture {
            if isSelected { selected.remove(shot.id) } else { selected.insert(shot.id) }
        }
        .accessibilityLabel("Frame, \(isSelected ? "selected" : "not selected"). Double tap to inspect.")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            OSPrimaryButton(title: saving ? "Saving…" : "Save roll (\(selected.count))",
                            enabled: !saving && !selected.isEmpty) {
                saveSelected()
            }
            Button("Close without saving") { onDone() }
                .font(OSFont.label(13))
                .foregroundStyle(OSColor.inkFaint)
        }
        .padding(16)
    }

    /// Exports selected shots to Photos sequentially. HF-72 diptych pairs
    /// share one composed image — dedupe by file contents ID (shot pairs write
    /// identical files, so export the first of each pair only).
    private func saveSelected() {
        guard let roll else { return }
        saving = true
        let shots = roll.shots.filter { selected.contains($0.id) }
        Task {
            var saved = 0
            var skipNext = false
            for (index, shot) in shots.enumerated() {
                if skipNext { skipNext = false; continue }
                if roll.cameraID == .hf72, index + 1 < shots.count { skipNext = true }
                let ok = await withCheckedContinuation { continuation in
                    ExportManager.saveToPhotos(rollID: rollID, shot: shot) { success in
                        continuation.resume(returning: success)
                    }
                }
                if ok { saved += 1 }
            }
            saving = false
            savedCount = saved
        }
    }
}

// MARK: - Per-photo detail

struct ReviewDetailSheet: View {
    @ObservedObject private var store = RollStore.shared
    let rollID: UUID
    let shotID: UUID

    @State private var showOriginal = false
    @State private var working = false
    @State private var showCameraSwitcher = false
    @Environment(\.dismiss) private var dismiss

    private var shot: Shot? {
        store.roll(rollID)?.shots.first { $0.id == shotID }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let shot {
                let image = showOriginal
                    ? store.originalImage(roll: rollID, shot: shot)
                    : store.developedImage(roll: rollID, shot: shot.id)
                Group {
                    if working {
                        ProgressView("Re-developing…")
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                .frame(maxHeight: 420)
                .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                    showOriginal = pressing
                }, perform: {})

                OSLabelText(text: "\(FilmStockLibrary.stock(for: shot.cameraID).displayName) · hold to compare", size: 11)

                HStack(spacing: 12) {
                    OSSecondaryButton(title: "Re-roll") {
                        rerender(camera: nil)
                    }
                    OSSecondaryButton(title: "Switch camera") {
                        showCameraSwitcher = true
                    }
                    OSSecondaryButton(title: "Remove") {
                        store.deleteShot(rollID: rollID, shotID: shotID)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 20)
        .presentationDetents([.large])
        .presentationBackground(OSColor.cream)
        .confirmationDialog("Switch camera", isPresented: $showCameraSwitcher, titleVisibility: .visible) {
            ForEach(FilmStockLibrary.all) { stock in
                if EntitlementGate.shared.canUse(camera: stock.id) {
                    Button(stock.displayName) { rerender(camera: stock.id) }
                }
            }
        }
    }

    private func rerender(camera: CameraID?) {
        working = true
        Task {
            await store.reRoll(rollID: rollID, shotID: shotID, newCamera: camera)
            working = false
        }
    }
}
