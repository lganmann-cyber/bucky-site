import SwiftUI

/// OldSnap visual identity v2 — Locket-style: near-black surfaces with a
/// warm glow, SF Pro Rounded bold type, big amber pill buttons with dark
/// text, softly rounded dark cards. Friendly, warm, nocturnal.
enum OSColor {
    /// Near-black app background (warm, never pure black).
    static let bg = Color(hex: 0x0E0D0B)
    /// Elevated dark surface: cards, choice rows, banners.
    static let surface = Color(hex: 0x1D1C19)
    /// Input fields / pressed surfaces, one step lighter.
    static let field = Color(hex: 0x262420)
    /// Primary text: warm off-white.
    static let textPrimary = Color(hex: 0xF5F3EF)
    /// Secondary text ~55% white.
    static let textSecondary = Color(hex: 0xF5F3EF).opacity(0.55)
    /// The amber accent — buttons, highlights, selection.
    static let accent = Color(hex: 0xFFC233)
    /// Text/icons sitting on the amber accent.
    static let onAccent = Color(hex: 0x201700)
    /// Retro date-stamp / lab-timer orange (unchanged; it's in the photos).
    static let stampOrange = Color(hex: 0xFF7A1A)
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

/// SF Pro Rounded everywhere — the friendly, bold look. No custom font
/// licenses needed; `design: .rounded` is the exact face in the reference.
enum OSFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }
    /// Digit face for date stamps and lab timers.
    static func stamp(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

/// The screen backdrop: warm black with a faint amber glow rising from the
/// bottom, like the reference onboarding.
struct OSScreenBackground: View {
    var body: some View {
        ZStack {
            OSColor.bg
            RadialGradient(
                colors: [OSColor.accent.opacity(0.14), .clear],
                center: .init(x: 0.5, y: 1.05),
                startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

/// Big bold sentence-case headline (SF Rounded), centered.
struct OSDisplayText: View {
    let text: String
    var size: CGFloat = 28
    var color: Color = OSColor.textPrimary

    var body: some View {
        Text(text)
            .font(OSFont.display(size))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OSLabelText: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = OSColor.textSecondary

    var body: some View {
        Text(text)
            .font(OSFont.label(size))
            .foregroundStyle(color)
    }
}

/// Primary CTA: full-width amber pill, bold dark label, trailing arrow.
/// Disabled state is the gray pill from the reference.
struct OSPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var showsArrow: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(OSFont.display(19))
                if showsArrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(enabled ? OSColor.onAccent : OSColor.textPrimary.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                Capsule().fill(enabled ? OSColor.accent : OSColor.surface))
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(title))
    }
}

/// Secondary action: dark gray pill, white label.
struct OSSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OSFont.display(16))
                .foregroundStyle(OSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(OSColor.surface))
        }
        .accessibilityLabel(Text(title))
    }
}

/// A tappable intake option: rounded dark card, bold white title.
struct OSChoiceRow: View {
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OSFont.display(17))
                    .foregroundStyle(OSColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(OSFont.body(14))
                        .foregroundStyle(OSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OSColor.surface))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rounded circular back/utility chip (dark gray), as in the reference.
struct OSCircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OSColor.textPrimary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(OSColor.surface))
        }
        .accessibilityLabel(label)
    }
}

/// Progress indicator: film sprocket holes, now soft rounded dots — amber
/// when filled, faint white when not.
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
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(filled ? OSColor.accent : OSColor.textPrimary.opacity(0.14))
                        .frame(width: holeWidth, height: 12)
                }
            }
        }
        .frame(height: 12)
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
