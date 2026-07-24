#if OLDSNAP_DEBUG_TOOLS
import SwiftUI
import PhotosUI

/// Dev-only calibration tool: renders one source photo through every preset
/// in a grid for side-by-side comparison against the reference scans in
/// Engine/Calibration. Reachable from Settings → Developer.
struct PresetComparisonView: View {
    @State private var source: UIImage?
    @State private var renders: [CameraID: UIImage] = [:]
    @State private var pickerItem: PhotosPickerItem?
    @State private var seed = SeededRandom.freshSeed()
    @State private var rendering = false
    @State private var zoomed: CameraID?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("PICK SOURCE").font(OSFont.label(13)).kerning(1)
                    }
                    Spacer()
                    Button("RE-SEED") {
                        seed = SeededRandom.freshSeed()
                        renderAll()
                    }
                    .font(OSFont.label(13)).kerning(1)
                }
                .padding(.horizontal)

                if rendering { ProgressView("Rendering \(renders.count)/\(FilmStockLibrary.all.count)") }

                if let source {
                    labeledCell(title: "ORIGINAL", image: source, id: nil)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FilmStockLibrary.all) { stock in
                            if let img = renders[stock.id] {
                                labeledCell(title: "\(stock.displayName) · \(stock.eraTag)",
                                            image: img, id: stock.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Text("Pick a source photo to render the full preset grid.")
                        .font(OSFont.body(15))
                        .foregroundStyle(OSColor.inkFaint)
                        .padding(.top, 60)
                }
            }
            .padding(.vertical)
        }
        .background(OSColor.cream)
        .navigationTitle("Preset Grid")
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // Calibrate at moderate size so the grid iterates fast.
                    source = image.osScaledDown(maxEdge: 1600)
                    renderAll()
                }
            }
        }
        .sheet(item: $zoomed) { id in
            zoomSheet(id: id)
        }
    }

    private func labeledCell(title: String, image: UIImage, id: CameraID?) -> some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .onTapGesture { zoomed = id }
            OSLabelText(text: title, size: 10)
        }
    }

    private func zoomSheet(id: CameraID) -> some View {
        VStack(spacing: 12) {
            if let img = renders[id] {
                Image(uiImage: img).resizable().scaledToFit()
            }
            let stock = FilmStockLibrary.stock(for: id)
            OSDisplayText(text: stock.displayName, size: 22)
            Text(stock.tagline).font(OSFont.body(14)).foregroundStyle(OSColor.inkFaint)
        }
        .padding()
        .presentationBackground(OSColor.cream)
    }

    private func renderAll() {
        guard let source else { return }
        rendering = true
        renders = [:]
        let currentSeed = seed
        Task.detached(priority: .userInitiated) {
            for stock in FilmStockLibrary.all {
                let options = FilmEngine.RenderOptions(
                    seed: currentSeed, quality: .full,
                    dateStamp: stock.dateStampDefault ? .retroRandom : .off)
                let rendered = FilmEngine.shared.developUIImage(
                    source: source, stock: stock, options: options)
                await MainActor.run {
                    if let rendered { renders[stock.id] = rendered }
                }
            }
            await MainActor.run { rendering = false }
        }
    }
}

extension UIImage {
    func osScaledDown(maxEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxEdge else { return self }
        let scale = maxEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
