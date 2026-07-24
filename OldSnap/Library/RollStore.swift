import Foundation
import UIKit
import Photos
import UserNotifications
import Combine

/// Single source of truth for rolls and their image files. Rolls persist as
/// JSON in Application Support; images live under Documents/Rolls/<rollID>/.
/// Everything survives app kill: rolls, the active roll, develop timers
/// (stored as absolute end dates), and undeveloped shots (re-enqueued on launch).
@MainActor
final class RollStore: ObservableObject {
    static let shared = RollStore()

    @Published private(set) var rolls: [Roll] = []
    @Published private(set) var activeRollID: UUID?
    /// Live develop-queue progress, keyed by roll: (done, total).
    @Published var developProgress: [UUID: (Int, Int)] = [:]

    private let queue = DevelopQueue()
    private var timers: [UUID: Timer] = [:]

    // MARK: - Paths

    private nonisolated var rollsRootURL: URL { RollFiles.rootURL }
    private var indexURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("rolls.json")
    }

    nonisolated func originalURL(roll: UUID, shot: UUID) -> URL {
        RollFiles.originalURL(roll: roll, shot: shot)
    }
    nonisolated func developedURL(roll: UUID, shot: UUID) -> URL {
        RollFiles.developedURL(roll: roll, shot: shot)
    }

    private init() {
        load()
        resumeInterruptedWork()
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var rolls: [Roll]
        var activeRollID: UUID?
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        rolls = state.rolls
        activeRollID = state.activeRollID
    }

    private func save() {
        let state = PersistedState(rolls: rolls, activeRollID: activeRollID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    /// Re-arms develop timers and re-enqueues unfinished renders after a kill.
    private func resumeInterruptedWork() {
        for roll in rolls {
            switch roll.state {
            case .developing(let endsAt):
                enqueueUndevelopedShots(of: roll)
                armTimer(rollID: roll.id, endsAt: max(endsAt, Date().addingTimeInterval(1)))
            case .developed:
                // A kill mid-render can leave developed rolls with missing files.
                if roll.shots.contains(where: { !$0.isDeveloped }) {
                    enqueueUndevelopedShots(of: roll)
                }
            case .active:
                break
            }
        }
    }

    // MARK: - Roll lifecycle

    func roll(_ id: UUID?) -> Roll? {
        guard let id else { return nil }
        return rolls.first { $0.id == id }
    }

    var activeRoll: Roll? { roll(activeRollID) }

    /// Live-shot path: returns the active roll for a camera, starting a fresh
    /// one when needed (camera switch mid-roll keeps the roll; film purists
    /// can pretend it's a mid-roll swap).
    func ensureActiveRoll(camera: CameraID) -> Roll {
        if let current = activeRoll, current.state == .active { return current }
        let fresh = Roll(id: UUID(), cameraID: camera, createdAt: Date(),
                         source: .liveShot, shots: [], state: .active)
        rolls.insert(fresh, at: 0)
        activeRollID = fresh.id
        try? FileManager.default.createDirectory(
            at: rollsRootURL.appendingPathComponent(fresh.id.uuidString),
            withIntermediateDirectories: true)
        Analytics.track(.rollStarted(camera: camera.rawValue))
        save()
        return fresh
    }

    /// Appends a captured shot (original JPEG data already in hand).
    /// Returns false when the roll is full — the camera should wind on to a
    /// fresh roll and send the full one to the lab.
    @discardableResult
    func addShot(toRoll rollID: UUID, cameraID: CameraID, originalJPEG: Data,
                 stampMode: Shot.StampMode, assetIdentifier: String? = nil) -> Shot? {
        guard var roll = roll(rollID), roll.state == .active, !roll.isFull else { return nil }
        let shot = Shot(id: UUID(), cameraID: cameraID, seed: SeededRandom.freshSeed(),
                        capturedAt: Date(), sourceAssetIdentifier: assetIdentifier,
                        stampMode: stampMode)
        try? FileManager.default.createDirectory(
            at: rollsRootURL.appendingPathComponent(rollID.uuidString),
            withIntermediateDirectories: true)
        do {
            try originalJPEG.write(to: originalURL(roll: rollID, shot: shot.id), options: .atomic)
        } catch {
            return nil
        }
        roll.shots.append(shot)
        update(roll)
        if roll.isFull { sendToLab(rollID: rollID) }
        return shot
    }

    /// Moves a roll into the developing state: 30-second lab timer, renders
    /// run during the wait, local notification on completion.
    func sendToLab(rollID: UUID) {
        guard var roll = roll(rollID), roll.state == .active, !roll.shots.isEmpty else { return }
        let endsAt = Date().addingTimeInterval(AppConfig.rollDevelopSeconds)
        roll.state = .developing(endsAt: endsAt)
        update(roll)
        if activeRollID == rollID { activeRollID = nil; save() }
        enqueueUndevelopedShots(of: roll)
        armTimer(rollID: rollID, endsAt: endsAt)
        NotificationManager.shared.scheduleRollReady(rollID: rollID, at: endsAt)
    }

    private func armTimer(rollID: UUID, endsAt: Date) {
        timers[rollID]?.invalidate()
        let timer = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishDevelopingIfReady(rollID: rollID) }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[rollID] = timer
    }

    /// A roll is done when both the lab timer elapsed AND every render landed.
    func finishDevelopingIfReady(rollID: UUID) {
        guard var roll = roll(rollID), case .developing(let endsAt) = roll.state else { return }
        guard Date() >= endsAt else { return }
        guard roll.shots.allSatisfy(\.isDeveloped) else { return } // queue will re-check
        roll.state = .developed
        update(roll)
        timers[rollID]?.invalidate()
        timers[rollID] = nil
        Analytics.track(.rollDeveloped)
    }

    func update(_ roll: Roll) {
        if let idx = rolls.firstIndex(where: { $0.id == roll.id }) {
            rolls[idx] = roll
        } else {
            rolls.insert(roll, at: 0)
        }
        save()
    }

    func deleteRoll(_ rollID: UUID) {
        timers[rollID]?.invalidate()
        timers[rollID] = nil
        rolls.removeAll { $0.id == rollID }
        if activeRollID == rollID { activeRollID = nil }
        try? FileManager.default.removeItem(at: rollsRootURL.appendingPathComponent(rollID.uuidString))
        save()
    }

    func deleteShot(rollID: UUID, shotID: UUID) {
        guard var roll = roll(rollID) else { return }
        roll.shots.removeAll { $0.id == shotID }
        try? FileManager.default.removeItem(at: originalURL(roll: rollID, shot: shotID))
        try? FileManager.default.removeItem(at: developedURL(roll: rollID, shot: shotID))
        if roll.shots.isEmpty {
            deleteRoll(rollID)
        } else {
            update(roll)
        }
    }

    // MARK: - Rendering

    private func enqueueUndevelopedShots(of roll: Roll) {
        let pending = roll.shots.filter { !$0.isDeveloped }
        guard !pending.isEmpty else { return }
        developProgress[roll.id] = (roll.shots.count - pending.count, roll.shots.count)
        Task {
            await queue.enqueue(rollID: roll.id, shots: pending, store: self)
        }
    }

    /// Called by the queue when one render lands.
    func markDeveloped(rollID: UUID, shotID: UUID) {
        guard var roll = roll(rollID) else { return }
        guard let idx = roll.shots.firstIndex(where: { $0.id == shotID }) else { return }
        roll.shots[idx].isDeveloped = true
        update(roll)
        let done = roll.shots.filter(\.isDeveloped).count
        developProgress[rollID] = (done, roll.shots.count)
        if done == roll.shots.count {
            developProgress[rollID] = nil
            finishDevelopingIfReady(rollID: rollID)
        }
    }

    /// Re-render a single shot with a fresh seed ("re-roll variation") or a
    /// different camera. Synchronous render on a background task.
    func reRoll(rollID: UUID, shotID: UUID, newCamera: CameraID? = nil) async {
        guard var roll = roll(rollID),
              let idx = roll.shots.firstIndex(where: { $0.id == shotID }) else { return }
        roll.shots[idx].seed = SeededRandom.freshSeed()
        if let newCamera { roll.shots[idx].cameraID = newCamera }
        roll.shots[idx].isDeveloped = false
        update(roll)
        let shot = roll.shots[idx]
        let watermark = !EntitlementGate.shared.canUseWithoutWatermark(camera: shot.cameraID)
        await queue.renderNow(rollID: rollID, shot: shot, store: self, watermark: watermark)
    }

    // MARK: - Image access

    nonisolated func originalImage(roll: UUID, shot: Shot) -> UIImage? {
        if let img = UIImage(contentsOfFile: originalURL(roll: roll, shot: shot.id).path) {
            return img
        }
        // Original was cache-cleared; re-fetch synchronously from Photos.
        guard let assetID = shot.sourceAssetIdentifier,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
        else { return nil }
        var result: UIImage?
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize,
            contentMode: .default, options: options) { image, _ in result = image }
        return result
    }

    nonisolated func developedImage(roll: UUID, shot: UUID) -> UIImage? {
        UIImage(contentsOfFile: developedURL(roll: roll, shot: shot).path)
    }

    // MARK: - Storage management

    func storageBytesUsed() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rollsRootURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Deletes sandbox originals that can be re-fetched from Photos.
    /// Developed renders are never touched.
    func clearRefetchableOriginals() {
        for roll in rolls {
            for shot in roll.shots where shot.sourceAssetIdentifier != nil && shot.isDeveloped {
                try? FileManager.default.removeItem(at: originalURL(roll: roll.id, shot: shot.id))
            }
        }
        objectWillChange.send()
    }
}

// MARK: - Local notifications

/// Owns the notification permission flow. The ask NEVER happens in
/// onboarding: the purpose prompt appears after the user's first roll
/// finishes developing, and only then do we request the system permission.
final class NotificationManager {
    static let shared = NotificationManager()

    private let promptedKey = "os.notifications.prompted"

    var hasPrompted: Bool {
        UserDefaults.standard.bool(forKey: promptedKey)
    }

    /// Call after showing the "Want to know when your prints are ready?" screen.
    func requestPermission() async -> Bool {
        UserDefaults.standard.set(true, forKey: promptedKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        Analytics.track(.notificationPermission(granted: granted))
        return granted
    }

    func scheduleRollReady(rollID: UUID, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Your prints are ready"
        content.body = "A fresh roll just finished developing. Come see it."
        content.sound = .default
        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "roll-\(rollID.uuidString)",
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
