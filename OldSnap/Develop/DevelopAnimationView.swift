import SwiftUI

/// The single-photo develop moment (~2.5 s): the original surfaces from black,
/// color character fades in, grain crawls in, and the date stamp burns last.
/// Skippable with a tap after the user has seen it once. Reduce Motion cuts
/// straight to the finished print.
struct DevelopAnimationView: View {
    let rollID: UUID
    let shot: Shot
    let onFinished: () -> Void

    @ObservedObject private var store = RollStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Double = 0 // 0 → 1 across the animation
    @State private var finished = false

    private static let seenKey = "os.developAnimation.seen"

    var body: some View {
        let original = store.originalImage(roll: rollID, shot: shot)
        let developed = store.developedImage(roll: rollID, shot: shot.id)

        VStack(spacing: 24) {
            Spacer()
            ZStack {
                if let original {
                    Image(uiImage: original)
                        .resizable().scaledToFit()
                        .saturation(1 - phase)          // color character takes over
                        .opacity(1 - phase)
                }
                if let developed {
                    Image(uiImage: developed)
                        .resizable().scaledToFit()
                        .opacity(phase)                  // grain + stamp arrive with it
                }
            }
            .background(Color.black)
            .brightness(phase < 0.15 ? -0.9 * (0.15 - phase) / 0.15 : 0) // out of the dark bath
            .padding(.horizontal, 24)

            OSLabelText(text: finished ? "Developed" : "Developing…", size: 13)
            Spacer()

            if finished {
                OSPrimaryButton(title: "Continue") { onFinished() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x191813).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            // Skippable once the magic has been seen before.
            if !finished, UserDefaults.standard.bool(forKey: Self.seenKey) {
                complete()
            }
        }
        .onAppear { start() }
    }

    private func start() {
        if reduceMotion {
            complete()
            return
        }
        withAnimation(.easeInOut(duration: 2.5)) { phase = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if !finished { complete() }
        }
    }

    private func complete() {
        phase = 1
        finished = true
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }
}
