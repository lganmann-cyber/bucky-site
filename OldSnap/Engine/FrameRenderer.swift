import UIKit
import CoreText

/// Final CG compositing pass: frame treatments, date stamps, dust, and the
/// free-tier watermark. Runs at full output resolution after the CI pipeline.
enum FrameRenderer {
    // MARK: - Composition

    static func compose(image: CGImage, stock: FilmStock,
                        options: FilmEngine.RenderOptions) -> UIImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvas: CGRect
        let imageRect: CGRect

        switch stock.frame {
        case .instantWhite:
            // Classic instant proportions: even border, thick chin.
            let border = imageSize.width * 0.055
            let chin = imageSize.width * 0.20
            canvas = CGRect(x: 0, y: 0,
                            width: imageSize.width + border * 2,
                            height: imageSize.height + border + chin)
            imageRect = CGRect(x: border, y: border,
                               width: imageSize.width, height: imageSize.height)
        case .none, .halfFrameDiptych:
            canvas = CGRect(origin: .zero, size: imageSize)
            imageRect = canvas
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvas.size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            if stock.frame == .instantWhite {
                // Warm print-paper white with a faint edge shadow on the image well.
                UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
                cg.fill(canvas)
            }

            // UIKit context is top-left origin; draw the CGImage flipped.
            cg.saveGState()
            cg.translateBy(x: 0, y: canvas.height)
            cg.scaleBy(x: 1, y: -1)
            let flippedRect = CGRect(x: imageRect.minX,
                                     y: canvas.height - imageRect.maxY,
                                     width: imageRect.width, height: imageRect.height)
            cg.draw(image, in: flippedRect)
            cg.restoreGState()

            if stock.frame == .instantWhite {
                cg.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
                cg.setLineWidth(max(imageSize.width * 0.002, 1))
                cg.stroke(imageRect)
            }

            var rng = SeededRandom(seed: options.seed ^ 0x6672_616D)

            if options.dateStamp != .off {
                drawDateStamp(in: cg, imageRect: imageRect,
                              mode: options.dateStamp, rng: &rng)
            }

            if options.quality == .full, rng.chance(stock.artifacts.dustChance) {
                drawDust(in: cg, rect: imageRect, rng: &rng)
            }

            if options.watermark {
                drawWatermark(in: cg, rect: imageRect)
            }
        }
    }

    /// HF-72: two half-frames side by side in one 35mm frame with a thin
    /// exposed-film gutter — the format's signature share shape.
    static func diptych(left: UIImage, right: UIImage) -> UIImage? {
        guard let l = left.cgImage, let r = right.cgImage else { return nil }
        // Each half-frame is portrait; the pair lands close to 3:2 landscape.
        let halfHeight = CGFloat(min(l.height, r.height))
        let halfWidth = halfHeight * (2.0 / 3.0)
        let gutter = halfWidth * 0.045
        let size = CGSize(width: halfWidth * 2 + gutter, height: halfHeight)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // The gutter is unexposed film: near-black with a warm cast.
            UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawFilling(left, into: CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), context: ctx.cgContext)
            drawFilling(right, into: CGRect(x: halfWidth + gutter, y: 0, width: halfWidth, height: halfHeight), context: ctx.cgContext)
        }
    }

    private static func drawFilling(_ image: CGImage, into rect: CGRect, context cg: CGContext) {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let rectAspect = rect.width / rect.height
        var drawRect = rect
        if imageAspect > rectAspect {
            let w = rect.height * imageAspect
            drawRect = CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height)
        } else {
            let h = rect.width / imageAspect
            drawRect = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        }
        cg.saveGState()
        cg.clip(to: rect)
        cg.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: drawRect)
        cg.restoreGState()
    }

    // MARK: - Date stamp

    /// Burned-in orange quartz-date-back stamp, bottom right, with bloom.
    /// Retro mode fabricates a plausible 90s date from the seed so the stamp
    /// is stable across re-renders of the same shot.
    private static func drawDateStamp(in cg: CGContext, imageRect: CGRect,
                                      mode: FilmEngine.DateStampMode,
                                      rng: inout SeededRandom) {
        let text: String
        switch mode {
        case .off:
            return
        case .retroRandom:
            let year = 90 + Int(rng.next() % 10)          // '90–'99
            let month = 1 + Int(rng.next() % 12)
            let day = 1 + Int(rng.next() % 28)
            text = String(format: "'%02d %2d %2d", year, month, day)
        case .actual(let date):
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            text = String(format: "'%02d %2d %2d", (c.year ?? 2000) % 100, c.month ?? 1, c.day ?? 1)
        }

        let fontSize = imageRect.width * 0.038
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let stampColor = UIColor(red: 1.0, green: 0.48, blue: 0.10, alpha: 0.92)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: stampColor,
            .kern: fontSize * 0.12,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let origin = CGPoint(x: imageRect.maxX - textSize.width - imageRect.width * 0.05,
                             y: imageRect.maxY - textSize.height - imageRect.height * 0.045)

        // The LED bleed: soft orange glow behind the digits.
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: fontSize * 0.45,
                     color: stampColor.withAlphaComponent(0.9).cgColor)
        string.draw(at: origin)
        string.draw(at: origin) // second pass strengthens the burn
        cg.restoreGState()
    }

    // MARK: - Dust

    private static func drawDust(in cg: CGContext, rect: CGRect, rng: inout SeededRandom) {
        cg.saveGState()
        let count = 4 + Int(rng.next() % 6)
        for _ in 0..<count {
            let x = rect.minX + CGFloat(rng.unit()) * rect.width
            let y = rect.minY + CGFloat(rng.unit()) * rect.height
            let isScratch = rng.chance(0.25)
            let alpha = CGFloat(rng.uniform(0.05...0.16))
            cg.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            if isScratch {
                let length = rect.height * CGFloat(rng.uniform(0.02...0.08))
                cg.fill(CGRect(x: x, y: y, width: max(rect.width * 0.0006, 0.8), height: length))
            } else {
                let d = rect.width * CGFloat(rng.uniform(0.0008...0.002))
                cg.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
            }
        }
        cg.restoreGState()
    }

    // MARK: - Watermark (lapsed free tier only)

    private static func drawWatermark(in cg: CGContext, rect: CGRect) {
        let fontSize = rect.width * 0.028
        let string = NSAttributedString(string: "oldsnap", attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            .kern: fontSize * 0.18,
        ])
        let size = string.size()
        string.draw(at: CGPoint(x: rect.minX + rect.width * 0.04,
                                y: rect.maxY - size.height - rect.height * 0.03))
    }
}
