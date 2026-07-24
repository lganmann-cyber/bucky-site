import UIKit
import Photos

/// Saving and sharing developed prints. Exports run at full source resolution
/// with EXIF preserved from the sandbox original where possible.
enum ExportManager {
    enum Format { case jpeg, heic }

    /// Saves a developed shot to the system photo library, carrying over the
    /// original's EXIF/metadata dictionary.
    static func saveToPhotos(rollID: UUID, shot: Shot, format: Format = .jpeg,
                             completion: @escaping (Bool) -> Void) {
        let store = RollStore.shared
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = exportData(rollID: rollID, shot: shot, format: format) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                DispatchQueue.main.async {
                    if success { Analytics.track(.photoSaved) }
                    completion(success)
                }
            }
            _ = store // keep the singleton referenced explicitly
        }
    }

    /// Developed image data with the original's metadata merged in.
    static func exportData(rollID: UUID, shot: Shot, format: Format) -> Data? {
        let store = RollStore.shared
        let developedURL = store.developedURL(roll: rollID, shot: shot.id)
        guard let developed = try? Data(contentsOf: developedURL) else { return nil }

        // Pull EXIF from the sandbox original; if it's gone, ship as-is.
        let originalURL = store.originalURL(roll: rollID, shot: shot.id)
        guard let originalSource = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil),
              let developedSource = CGImageSourceCreateWithData(developed as CFData, nil)
        else { return developed }

        let uti = (format == .heic ? "public.heic" : "public.jpeg") as CFString
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else { return developed }
        CGImageDestinationAddImageFromSource(dest, developedSource, 0, metadata)
        guard CGImageDestinationFinalize(dest) else { return developed }
        return out as Data
    }

    /// "shot on OldSnap · 35C" — copied to the clipboard alongside shares.
    static func copyShareCaption(camera: CameraID) {
        let stock = FilmStockLibrary.stock(for: camera)
        UIPasteboard.general.string = "shot on OldSnap · \(stock.displayName)"
    }
}

/// UIKit share-sheet bridge.
import SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
