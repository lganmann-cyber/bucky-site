import SwiftUI

/// Procedurally drawn skeuomorphic camera bodies for the picker shelf and
/// paywall. No image assets: each silhouette family is drawn from the stock's
/// `CameraBodyStyle`, so a designer swap later is one view.
struct CameraBodyView: View {
    let stock: FilmStock

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let body = Color(hex: stock.bodyStyle.bodyHex)
            let plate = Color(hex: stock.bodyStyle.plateHex)
            let accent = Color(hex: stock.bodyStyle.accentHex)

            ZStack {
                // Body slab
                Rectangle().fill(body)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.25), lineWidth: 1))

                // Faceplate band
                Rectangle().fill(plate)
                    .frame(height: h * plateBandHeight)
                    .offset(y: plateBandOffset * h)

                // Lens
                Circle().fill(Color(hex: 0x101010))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .overlay(Circle().fill(Color(hex: 0x2E3A55)).scaleEffect(0.55))
                    .frame(width: lensSize * h, height: lensSize * h)
                    .offset(lensOffset(w: w, h: h))

                // Viewfinder window
                Rectangle().fill(Color(hex: 0x0A0A0A))
                    .frame(width: w * 0.14, height: h * 0.12)
                    .offset(x: -w * 0.3, y: -h * 0.3)

                // Flash
                if hasFlash {
                    Rectangle().fill(Color(hex: 0xEFE8D0))
                        .overlay(Rectangle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                        .frame(width: w * 0.16, height: h * 0.10)
                        .offset(x: w * 0.3, y: -h * 0.3)
                }

                // Shutter button
                Circle().fill(accent)
                    .frame(width: h * 0.12, height: h * 0.12)
                    .offset(x: w * 0.32, y: -h * 0.44)

                // Model plate
                Text(stock.displayName)
                    .font(.system(size: h * 0.13, weight: .heavy).width(.condensed))
                    .foregroundStyle(body.osLuminanceIsDark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                    .offset(y: h * 0.32)
            }
        }
        .accessibilityLabel("\(stock.displayName) camera, \(stock.eraTag)")
    }

    private var hasFlash: Bool {
        [.c35, .dc2000, .l79, .sun200].contains(stock.id)
    }

    private var lensSize: CGFloat {
        switch stock.bodyStyle.shape {
        case .slr: return 0.62
        case .instantBox: return 0.5
        case .pocket110: return 0.34
        default: return 0.44
        }
    }

    private var plateBandHeight: CGFloat {
        stock.bodyStyle.shape == .instantBox ? 0.28 : 0.2
    }

    private var plateBandOffset: CGFloat {
        stock.bodyStyle.shape == .instantBox ? 0.36 : -0.38
    }

    private func lensOffset(w: CGFloat, h: CGFloat) -> CGSize {
        switch stock.bodyStyle.shape {
        case .compact35, .digicam: return CGSize(width: -w * 0.05, height: h * 0.05)
        case .pocket110: return CGSize(width: 0, height: 0)
        default: return .zero
        }
    }
}

extension Color {
    /// Rough luminance check for choosing legible plate text.
    var osLuminanceIsDark: Bool {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return true }
        let luma = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luma < 0.5
    }
}
