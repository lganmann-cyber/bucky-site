import Foundation

/// One exposure. The original always lives in the sandbox (and optionally in
/// Photos via `sourceAssetIdentifier`); the developed render is reproducible
/// from (original, cameraID, seed), which is what makes re-rolls and cache
/// clearing safe.
struct Shot: Codable, Identifiable, Equatable {
    let id: UUID
    var cameraID: CameraID
    var seed: UInt64
    var capturedAt: Date
    /// PHAsset localIdentifier when the shot came from the photo library —
    /// lets "clear cache" drop sandbox originals and re-fetch on demand.
    var sourceAssetIdentifier: String?
    /// Whether the date stamp burns in, and with which date.
    var stampMode: StampMode
    var isDeveloped: Bool = false

    enum StampMode: Codable, Equatable {
        case off
        case retroRandom
        case actual(Date)

        var engineMode: FilmEngine.DateStampMode {
            switch self {
            case .off: return .off
            case .retroRandom: return .retroRandom
            case .actual(let d): return .actual(d)
            }
        }
    }
}

/// Path scheme for roll images. Nonisolated on purpose: background queues,
/// export code, and the main-actor store all derive identical paths from here.
enum RollFiles {
    static var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rolls", isDirectory: true)
    }
    static func originalURL(roll: UUID, shot: UUID) -> URL {
        rootURL.appendingPathComponent("\(roll.uuidString)/\(shot.uuidString)-original.jpg")
    }
    static func developedURL(roll: UUID, shot: UUID) -> URL {
        rootURL.appendingPathComponent("\(roll.uuidString)/\(shot.uuidString)-developed.jpg")
    }
}

enum RollState: Codable, Equatable {
    case active                    // still accepting shots
    case developing(endsAt: Date)  // in the lab — 30s timer running
    case developed
}

enum RollSource: String, Codable {
    case liveShot
    case imported
}

/// A film roll: the only organizing unit in the library. Live rolls fill up
/// to 36 and then develop on a timer; imported rolls arrive as a batch.
struct Roll: Codable, Identifiable, Equatable {
    let id: UUID
    /// Camera the roll was started on. Imported "shuffle" rolls carry mixed
    /// cameras per shot and leave this nil.
    var cameraID: CameraID?
    var createdAt: Date
    var source: RollSource
    var shots: [Shot]
    var state: RollState

    var isFull: Bool { shots.count >= AppConfig.rollCapacity }

    var displayCameraName: String {
        if let cameraID { return FilmStockLibrary.stock(for: cameraID).displayName }
        return "MIXED"
    }

    var dateRangeText: String {
        guard let first = shots.first?.capturedAt else {
            return createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        let last = shots.last?.capturedAt ?? first
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return f.string(from: first)
        }
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}
