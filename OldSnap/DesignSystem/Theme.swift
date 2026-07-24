import SwiftUI

/// OldSnap visual identity: printed-cardstock surfaces, film-box typography,
/// zero border radius everywhere. Skeuomorphism lives in camera mode only.
enum OSColor {
    static let cream = Color(hex: 0xF2EDE2)   // warm cream surface
    static let ink = Color(hex: 0x2B2A26)     // near-black ink
    static let accent = Color(hex: 0xC75B39)  // faded film-box orange
    static let creamDim = Color(hex: 0xE7E0D2)
    static let inkFaint = Color(hex: 0x2B2A26).opacity(0.55)
    static let stampOrange = Color(hex: 0xFF7A1A) // date-stamp burn orange
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Condensed uppercase display + letterspaced small caps, built on system
/// fonts so no bundled font license is needed at v1. Swap for an Oswald-class
/// face by changing these two functions.
enum OSFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    /// 7-segment-adjacent look for date stamps and lab timers.
    static func stamp(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

struct OSDisplayText: View {
    let text: String
    var size: CGFloat = 28
    var color: Color = OSColor.ink

    var body: some View {
        Text(text.uppercased())
            .font(OSFont.display(size))
            .kerning(0.5)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OSLabelText: View {
    let text: String
    var size: CGFloat = 12
    var color: Color = OSColor.inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(OSFont.label(size))
            .kerning(2)
            .foregroundStyle(color)
    }
}

/// Primary action: a flat, sharp-cornered slab of accent orange.
struct OSPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(OSFont.display(18))
                .kerning(1)
                .foregroundStyle(OSColor.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? OSColor.accent : OSColor.inkFaint)
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(title))
    }
}

struct OSSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(OSFont.label(14))
                .kerning(1.5)
                .foregroundStyle(OSColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OSColor.cream)
                .overlay(Rectangle().stroke(OSColor.ink, lineWidth: 1.5))
        }
        .accessibilityLabel(Text(title))
    }
}

/// A tappable intake option rendered like a line on a printed order form.
struct OSChoiceRow: View {
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OSFont.display(18))
                    .foregroundStyle(OSColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(OSFont.body(14))
                        .foregroundStyle(OSColor.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(OSColor.creamDim)
            .overlay(Rectangle().stroke(OSColor.ink.opacity(0.15), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Progress indicator styled as 35mm film perforations advancing along the top.
/// Filled sprocket holes mark completed steps.
struct FilmPerforationProgress: View {
    let progress: Double // 0...1

    var body: some View {
        GeometryReader { geo in
            let holeCount = 14
            let holeWidth: CGFloat = 10
            let spacing = (geo.size.width - CGFloat(holeCount) * holeWidth) / CGFloat(holeCount - 1)
            HStack(spacing: spacing) {
                ForEach(0..<holeCount, id: \.self) { i in
                    let filled = Double(i) / Double(holeCount - 1) <= progress
                    Rectangle()
                        .fill(filled ? OSColor.accent : OSColor.ink.opacity(0.15))
                        .frame(width: holeWidth, height: 14)
                }
            }
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

extension View {
    /// Honors Reduce Motion: runs the animated variant only when allowed.
    /// The reduced variant cuts, it does not animate.
    func osAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducedMotionAnimation(animation: animation, value: value))
    }
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
