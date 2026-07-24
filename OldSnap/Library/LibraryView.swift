import SwiftUI

/// The library: film rolls, never a grid dump. Each roll shows a cover thumb,
/// camera name, date range, and shot count out of 36.
struct LibraryView: View {
    @ObservedObject private var store = RollStore.shared

    var body: some View {
        Group {
            if store.rolls.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.rolls) { roll in
                            NavigationLink(value: roll.id) {
                                RollCard(roll: roll)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(OSScreenBackground())
        .navigationTitle("Rolls")
        .navigationDestination(for: UUID.self) { rollID in
            RollDetailView(rollID: rollID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            OSDisplayText(text: "No rolls yet", size: 24)
            Text("Shoot with a camera or develop photos from your library — every roll ends up here.")
                .font(OSFont.body(15))
                .foregroundStyle(OSColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One roll in the list, styled like a boxed roll on a lab shelf.
struct RollCard: View {
    @ObservedObject private var store = RollStore.shared
    let roll: Roll

    var body: some View {
        HStack(spacing: 14) {
            coverThumb
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                OSDisplayText(text: roll.displayCameraName, size: 18)
                OSLabelText(text: roll.dateRangeText, size: 11)
                OSLabelText(text: "\(roll.shots.count) / \(AppConfig.rollCapacity) exposures", size: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(OSColor.surface))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverThumb: some View {
        if roll.state == .developed,
           let first = roll.shots.first,
           let img = store.developedImage(roll: roll.id, shot: first.id) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            // Undeveloped rolls stay dark — no peeking.
            ZStack {
                Rectangle().fill(Color(hex: 0x191813))
                Image(systemName: "film")
                    .foregroundStyle(OSColor.textPrimary.opacity(0.4))
                    .font(.system(size: 26))
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch roll.state {
        case .active:
            OSLabelText(text: "In camera", size: 10, color: OSColor.accent)
        case .developing(let endsAt):
            LabTimerView(endsAt: endsAt, compact: true)
        case .developed:
            Image(systemName: "checkmark")
                .foregroundStyle(OSColor.textPrimary.opacity(0.5))
        }
    }
}

/// The lab countdown, styled as a darkroom timer.
struct LabTimerView: View {
    let endsAt: Date
    var compact = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = max(Int(endsAt.timeIntervalSince(now).rounded()), 0)
        VStack(spacing: 2) {
            Text(String(format: "0:%02d", remaining))
                .font(OSFont.stamp(compact ? 15 : 34))
                .foregroundStyle(OSColor.stampOrange)
            if !compact {
                OSLabelText(text: "Developing", size: 11)
            }
        }
        .onReceive(tick) { now = $0 }
        .accessibilityLabel("Developing, \(remaining) seconds remaining")
    }
}

// MARK: - Roll detail

struct RollDetailView: View {
    @ObservedObject private var store = RollStore.shared
    let rollID: UUID

    @State private var viewerIndex: Int?
    @State private var showNotificationPrompt = false
    @Environment(\.dismiss) private var dismiss

    private var roll: Roll? { store.roll(rollID) }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        Group {
            if let roll {
                content(roll)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(OSScreenBackground())
        .navigationTitle(roll?.displayCameraName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let roll {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if roll.state == .active {
                            Button("Send to lab") { store.sendToLab(rollID: rollID) }
                        }
                        Button("Delete roll", role: .destructive) {
                            store.deleteRoll(rollID)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { index in
            if let roll { PhotoViewer(roll: roll, startIndex: index) }
        }
        .sheet(isPresented: $showNotificationPrompt) {
            NotificationPromptView()
                .presentationDetents([.medium])
        }
        .onChange(of: roll?.state) { state in
            // The retention beat: first roll finishes → offer notifications.
            if state == .developed, !NotificationManager.shared.hasPrompted {
                showNotificationPrompt = true
            }
        }
    }

    @ViewBuilder
    private func content(_ roll: Roll) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if case .developing(let endsAt) = roll.state {
                    labOrderHeader(roll: roll, endsAt: endsAt)
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(roll.shots.enumerated()), id: \.element.id) { index, shot in
                        frameCell(roll: roll, shot: shot)
                            .aspectRatio(1, contentMode: .fill)
                            .onTapGesture {
                                if roll.state == .developed { viewerIndex = index }
                            }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 12)
        }
    }

    private func labOrderHeader(roll: Roll, endsAt: Date) -> some View {
        VStack(spacing: 8) {
            LabTimerView(endsAt: endsAt)
            if let (done, total) = store.developProgress[roll.id] {
                OSLabelText(text: "Developing \(done) of \(total)…", size: 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(hex: 0x191813))
    }

    @ViewBuilder
    private func frameCell(roll: Roll, shot: Shot) -> some View {
        if roll.state == .developed, shot.isDeveloped,
           let img = store.developedImage(roll: roll.id, shot: shot.id) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            // Dark undeveloped frame with the frame number, like unexposed film.
            ZStack {
                Rectangle().fill(Color(hex: 0x14130F))
                if let idx = roll.shots.firstIndex(of: shot) {
                    Text("\(idx + 1)")
                        .font(OSFont.stamp(13))
                        .foregroundStyle(OSColor.textPrimary.opacity(0.25))
                }
            }
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Notification purpose prompt

/// Purpose screen shown before the system permission dialog — only ever after
/// the user's first roll develops, never during onboarding.
struct NotificationPromptView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            OSDisplayText(text: "Want to know when your prints are ready?", size: 24)
            Text("Rolls take a moment in the lab. We'll send one quiet ping when each roll finishes developing — nothing else, ever.")
                .font(OSFont.body(15))
                .foregroundStyle(OSColor.textSecondary)
                .multilineTextAlignment(.center)
            OSPrimaryButton(title: "Notify me") {
                Task {
                    _ = await NotificationManager.shared.requestPermission()
                    dismiss()
                }
            }
            Button("Not now") { dismiss() }
                .font(OSFont.label(14))
                .foregroundStyle(OSColor.textSecondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OSScreenBackground())
    }
}

// MARK: - Full-screen viewer

/// Swipeable viewer with press-and-hold before/after, share, save, delete.
struct PhotoViewer: View {
    @ObservedObject private var store = RollStore.shared
    let roll: Roll
    let startIndex: Int

    @State private var index: Int = 0
    @State private var showOriginal = false
    @State private var shareItems: [Any]?
    @State private var saveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(OSColor.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
                if let shot = currentShot {
                    OSLabelText(text: "\(index + 1) / \(roll.shots.count) · \(FilmStockLibrary.stock(for: shot.cameraID).displayName)",
                                size: 12, color: OSColor.textPrimary.opacity(0.7))
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)

            TabView(selection: $index) {
                ForEach(Array(roll.shots.enumerated()), id: \.element.id) { i, shot in
                    viewerImage(shot: shot)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            toolbar
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { index = startIndex }
        .sheet(isPresented: Binding(get: { shareItems != nil },
                                    set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
        .alert("Saved to Photos", isPresented: $saveConfirmation) {
            Button("OK", role: .cancel) {}
        }
    }

    private var currentShot: Shot? {
        roll.shots.indices.contains(index) ? roll.shots[index] : nil
    }

    @ViewBuilder
    private func viewerImage(shot: Shot) -> some View {
        let developed = store.developedImage(roll: roll.id, shot: shot.id)
        let original = showOriginal ? store.originalImage(roll: roll.id, shot: shot) : nil
        Group {
            if let img = original ?? developed {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
            showOriginal = pressing // press-and-hold shows the original
        }, perform: {})
        .accessibilityLabel("Developed photo. Press and hold to compare with the original.")
    }

    private var toolbar: some View {
        HStack(spacing: 40) {
            Button {
                guard let shot = currentShot else { return }
                ExportManager.saveToPhotos(rollID: roll.id, shot: shot) { ok in
                    saveConfirmation = ok
                }
            } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 20))
            }
            .accessibilityLabel("Save to Photos")

            Button {
                guard let shot = currentShot,
                      let data = ExportManager.exportData(rollID: roll.id, shot: shot, format: .jpeg),
                      let image = UIImage(data: data) else { return }
                ExportManager.copyShareCaption(camera: shot.cameraID)
                Analytics.track(.photoShared(camera: shot.cameraID.rawValue))
                shareItems = [image]
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 20))
            }
            .accessibilityLabel("Share")

            Button(role: .destructive) {
                guard let shot = currentShot else { return }
                store.deleteShot(rollID: roll.id, shotID: shot.id)
                if roll.shots.count <= 1 { dismiss() }
                index = min(index, max(roll.shots.count - 2, 0))
            } label: {
                Image(systemName: "trash").font(.system(size: 20))
            }
            .accessibilityLabel("Delete photo")
        }
        .foregroundStyle(OSColor.textPrimary)
        .padding(.vertical, 18)
    }
}
