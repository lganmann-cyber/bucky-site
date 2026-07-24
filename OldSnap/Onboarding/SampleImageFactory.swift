import UIKit

/// Synthesizes a placeholder "modern iPhone photo" (a clean sunset-beach
/// scene drawn in CG) and renders it through film stocks for the onboarding
/// hook and the aesthetic tiles. Real licensed sample photography should
/// replace `baseScene` before ship — the render path stays identical.
enum SampleImageFactory {
    private static var cache: [String: UIImage] = [:]

    /// A clean, saturated, digital-looking scene — the "before".
    static func baseScene(size: CGSize = CGSize(width: 900, height: 1200)) -> UIImage {
        if let cached = cache["base"] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // Sky gradient
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.35, green: 0.62, blue: 0.95, alpha: 1).cgColor,
                UIColor(red: 0.98, green: 0.75, blue: 0.45, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(sky, start: .zero,
                                  end: CGPoint(x: 0, y: size.height * 0.62), options: [])
            // Sun
            cg.setFillColor(UIColor(red: 1, green: 0.93, blue: 0.75, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: size.width * 0.6, y: size.height * 0.28,
                                      width: size.width * 0.18, height: size.width * 0.18))
            // Sea
            cg.setFillColor(UIColor(red: 0.16, green: 0.42, blue: 0.55, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: size.height * 0.58, width: size.width, height: size.height * 0.18))
            // Sand
            cg.setFillColor(UIColor(red: 0.87, green: 0.78, blue: 0.62, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: size.height * 0.76, width: size.width, height: size.height * 0.24))
            // Two figures
            cg.setFillColor(UIColor(red: 0.15, green: 0.13, blue: 0.12, alpha: 1).cgColor)
            for (x, h) in [(0.32, 0.16), (0.44, 0.13)] {
                let height = size.height * h
                cg.fillEllipse(in: CGRect(x: size.width * x, y: size.height * 0.72 - height * 0.32,
                                          width: height * 0.16, height: height * 0.16))
                cg.fill(CGRect(x: size.width * x + height * 0.02, y: size.height * 0.72 - height * 0.12,
                               width: height * 0.12, height: height * 0.6))
            }
        }
        cache["base"] = image
        return image
    }

    /// The base scene developed through a camera, cached per camera.
    static func developed(camera: CameraID) -> UIImage {
        let key = "dev-\(camera.rawValue)"
        if let cached = cache[key] { return cached }
        let stock = FilmStockLibrary.stock(for: camera)
        let options = FilmEngine.RenderOptions(
            seed: 0xDEAD_BEEF, quality: .full,
            dateStamp: stock.dateStampDefault ? .retroRandom : .off)
        let rendered = FilmEngine.shared.developUIImage(
            source: baseScene(), stock: stock, options: options) ?? baseScene()
        cache[key] = rendered
        return rendered
    }
}
