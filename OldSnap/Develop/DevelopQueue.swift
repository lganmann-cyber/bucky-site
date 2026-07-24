import Foundation
import UIKit

/// Serial background render queue. One photo at a time, full resolution,
/// inside autoreleasepools — a 36-shot roll of 12 MP sources runs memory-flat
/// (this is the spec's hard requirement; never load a batch of originals).
actor DevelopQueue {
    /// Renders a batch sequentially, reporting each completion to the store.
    func enqueue(rollID: UUID, shots: [Shot], store: RollStore) async {
        for shot in shots {
            let clean = await EntitlementGate.shared.canUseWithoutWatermark(camera: shot.cameraID)
            await renderNow(rollID: rollID, shot: shot, store: store, watermark: !clean)
        }
        // Half-frame rolls pair up after every half is rendered.
        await composeDiptychsIfNeeded(rollID: rollID, store: store)
    }

    /// Renders one shot and writes the developed JPEG next to the original.
    func renderNow(rollID: UUID, shot: Shot, store: RollStore, watermark: Bool) async {
        let developed: Data? = autoreleasepool {
            guard let original = store.originalImage(roll: rollID, shot: shot) else { return nil }
            let stock = FilmStockLibrary.stock(for: shot.cameraID)
            let stamp: FilmEngine.DateStampMode = {
                switch shot.stampMode {
                case .off: return stock.dateStampDefault ? .retroRandom : .off
                default: return shot.stampMode.engineMode
                }
            }()
            let options = FilmEngine.RenderOptions(
                seed: shot.seed, quality: .full, dateStamp: stamp, watermark: watermark)
            return FilmEngine.shared.developJPEG(source: original, stock: stock, options: options)
        }
        if let developed {
            try? developed.write(to: store.developedURL(roll: rollID, shot: shot.id), options: .atomic)
        }
        // Mark developed even on failure so a corrupt source can't wedge the
        // roll in the lab forever; the viewer falls back to the original.
        await store.markDeveloped(rollID: rollID, shotID: shot.id)
    }

    /// HF-72: consecutive pairs become one 35mm diptych. Both shots' developed
    /// files are overwritten with the composed frame (duplicated on disk, but
    /// per-shot actions in review stay trivially simple). An odd trailing shot
    /// stays a lone half-frame.
    private func composeDiptychsIfNeeded(rollID: UUID, store: RollStore) async {
        let roll = await store.roll(rollID)
        guard let roll, roll.cameraID == .hf72 else { return }
        let shots = roll.shots
        var index = 0
        while index + 1 < shots.count {
            let a = shots[index], b = shots[index + 1]
            autoreleasepool {
                guard let left = store.developedImage(roll: rollID, shot: a.id),
                      let right = store.developedImage(roll: rollID, shot: b.id),
                      let pair = FilmEngine.shared.composeDiptych(left: left, right: right),
                      let data = pair.jpegData(compressionQuality: 0.92) else { return }
                try? data.write(to: store.developedURL(roll: rollID, shot: a.id), options: .atomic)
                try? data.write(to: store.developedURL(roll: rollID, shot: b.id), options: .atomic)
            }
            index += 2
        }
    }
}
