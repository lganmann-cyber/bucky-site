import SwiftUI
import StoreKit

/// The intake flow (Cal AI pattern): the user articulates their own problem
/// across ~13 one-tap screens, receives a Film Profile, develops one of their
/// own photos free, then hits the hard paywall framed as activating that
/// profile. No trial-toggle theater, no timers, no fake urgency.
struct OnboardingFlow: View {
    enum Step: Int, CaseIterable {
        case hook, socialProof
        case feel, count, feed, filmExperience, aesthetic, destination, rating, creatorCode
        case computing, profileCard, magicMoment
        case paywall
    }

    @State private var step: Step = .hook
    @State private var answers = OnboardingProfile.load()
    @State private var profile: FilmProfile?
    @State private var magicImage: UIImage?
    let onComplete: (FilmProfile?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                FilmPerforationProgress(progress: progress)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OSColor.cream.ignoresSafeArea())
        .onAppear { Analytics.track(.onboardingStarted) }
    }

    private var showsProgress: Bool {
        step.rawValue >= Step.feel.rawValue && step.rawValue <= Step.creatorCode.rawValue
    }

    private var progress: Double {
        Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    private func advance(to next: Step) {
        Analytics.track(.onboardingStepCompleted(step: String(describing: step)))
        answers.save()
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hook: HookView { advance(to: .socialProof) }
        case .socialProof: SocialProofView { advance(to: .feel) }
        case .feel:
            IntakeChoiceView(
                title: "How do your photos feel right now?",
                options: OnboardingProfile.PhotosFeel.allCases.map(\.label)) { index in
                    answers.photosFeel = OnboardingProfile.PhotosFeel.allCases[index]
                    advance(to: .count)
                }
        case .count:
            PhotoCountView(count: $answers.photoCount) { advance(to: .feed) }
        case .feed:
            IntakeChoiceView(
                title: "When film photos show up on your feed, you feel…",
                options: OnboardingProfile.FeedFeeling.allCases.map(\.label)) { index in
                    answers.feedFeeling = OnboardingProfile.FeedFeeling.allCases[index]
                    advance(to: .filmExperience)
                }
        case .filmExperience:
            FilmExperienceView { choice in
                answers.filmExperience = choice
                advance(to: .aesthetic)
            }
        case .aesthetic:
            AestheticTilesView { choice in
                answers.aesthetic = choice
                advance(to: .destination)
            }
        case .destination:
            IntakeChoiceView(
                title: "Where do your photos end up?",
                options: OnboardingProfile.Destination.allCases.map(\.label)) { index in
                    answers.destination = OnboardingProfile.Destination.allCases[index]
                    advance(to: .rating)
                }
        case .rating:
            RatingRequestView { advance(to: .creatorCode) }
        case .creatorCode:
            CreatorCodeView { code in
                answers.creatorCode = code
                advance(to: .computing)
            }
        case .computing:
            ComputingView {
                let generated = FilmProfileMatrix.profile(for: answers)
                profile = generated
                answers.generatedProfileName = generated.id
                answers.save()
                Analytics.track(.profileGenerated(profile: generated.id))
                advance(to: .profileCard)
            }
        case .profileCard:
            if let profile {
                ProfileCardView(profile: profile) { advance(to: .magicMoment) }
            }
        case .magicMoment:
            if let profile {
                MagicMomentView(profile: profile) { image in
                    magicImage = image
                    Analytics.track(.magicMomentCompleted)
                    Analytics.track(.paywallShown(source: "onboarding"))
                    advance(to: .paywall)
                }
            }
        case .paywall:
            PaywallView(source: "onboarding",
                        profileName: profile?.id,
                        heroImage: magicImage,
                        matchedCameras: profile?.cameras ?? []) {
                answers.completed = true
                answers.save()
                onComplete(profile)
            }
        }
    }
}

// MARK: - Phase 1: Hook

/// Full-bleed transformation: the modern photo dissolves into its 35C render,
/// looping gently. (Sample scene is synthesized; swap for licensed photography.)
struct HookView: View {
    let onNext: () -> Void
    @State private var showDeveloped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Image(uiImage: SampleImageFactory.baseScene())
                    .resizable().scaledToFill()
                Image(uiImage: SampleImageFactory.developed(camera: .c35))
                    .resizable().scaledToFill()
                    .opacity(showDeveloped ? 1 : 0)
            }
            .frame(maxHeight: 420)
            .clipped()
            .onAppear {
                guard !reduceMotion else { showDeveloped = true; return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)
                    .delay(0.6)) { showDeveloped = true }
            }
            .accessibilityHidden(true)

            OSDisplayText(text: "Make your camera roll feel like memories again.", size: 30)
                .padding(.horizontal, 28)
            Spacer()
            OSPrimaryButton(title: "Get started") { onNext() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .padding(.top, 8)
    }
}

struct SocialProofView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(OSColor.accent)
                }
            }
            .accessibilityLabel("Five stars")
            if let count = AppConfig.socialProofCount {
                OSDisplayText(text: "\(count.formatted()) people shoot film here", size: 24)
            }
            Text("Loved by people who miss how photos used to feel.")
                .font(OSFont.body(17))
                .foregroundStyle(OSColor.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            OSPrimaryButton(title: "Continue") { onNext() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
    }
}

// MARK: - Phase 2: Intake building blocks

/// One question, big tappable options, auto-advance.
struct IntakeChoiceView: View {
    let title: String
    let options: [String]
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 18) {
            OSDisplayText(text: title, size: 26)
                .padding(.horizontal, 28)
                .padding(.top, 40)
            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    OSChoiceRow(title: options[index]) { onPick(index) }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

struct PhotoCountView: View {
    @Binding var count: Double
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            OSDisplayText(text: "How many photos are on your phone?", size: 26)
                .padding(.horizontal, 28)
                .padding(.top, 40)

            OSDisplayText(text: countText, size: 44, color: OSColor.accent)
            Slider(value: $count, in: 500...50000, step: 100)
                .tint(OSColor.accent)
                .padding(.horizontal, 32)
                .accessibilityLabel("Photo count")
                .accessibilityValue(countText)

            // Their number, reflected back — the problem stated in their scale.
            Text("That's \(countText) memories that all look the same.")
                .font(OSFont.body(16))
                .foregroundStyle(OSColor.inkFaint)
                .padding(.horizontal, 40)
                .multilineTextAlignment(.center)

            Spacer()
            OSPrimaryButton(title: "Continue") { onNext() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
    }

    private var countText: String {
        count >= 50000 ? "50,000+" : Int(count).formatted()
    }
}

struct FilmExperienceView: View {
    let onPick: (OnboardingProfile.FilmExperience) -> Void
    @State private var picked: OnboardingProfile.FilmExperience?

    var body: some View {
        VStack(spacing: 18) {
            OSDisplayText(text: "Ever shot real film?", size: 26)
                .padding(.top, 40)
            VStack(spacing: 10) {
                ForEach(OnboardingProfile.FilmExperience.allCases, id: \.self) { option in
                    OSChoiceRow(title: option.label,
                                subtitle: picked == option ? option.response : nil) {
                        guard picked == nil else { return }
                        picked = option
                        // Let the tailored response land before advancing.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            onPick(option)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

/// Q7: four large aesthetic tiles, each the sample scene developed through
/// that aesthetic's primary camera. The main Film Profile signal.
struct AestheticTilesView: View {
    let onPick: (OnboardingProfile.Aesthetic) -> Void
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 18) {
            OSDisplayText(text: "Pick the photo you wish you took", size: 26)
                .padding(.horizontal, 28)
                .padding(.top, 32)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(OnboardingProfile.Aesthetic.allCases, id: \.self) { aesthetic in
                    Button { onPick(aesthetic) } label: {
                        VStack(spacing: 6) {
                            Image(uiImage: SampleImageFactory.developed(camera: aesthetic.primaryCamera))
                                .resizable().scaledToFill()
                                .frame(height: 190)
                                .clipped()
                            OSLabelText(text: aesthetic.label, size: 11, color: OSColor.ink)
                        }
                    }
                    .accessibilityLabel(aesthetic.label)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

/// The one and only rating ask, with the honest indie framing first.
struct RatingRequestView: View {
    let onNext: () -> Void
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            OSDisplayText(text: "OldSnap is built by one person, not a studio.", size: 28)
                .padding(.horizontal, 28)
            Text("A rating keeps the lights on 🖤")
                .font(OSFont.body(17))
                .foregroundStyle(OSColor.ink)
            Spacer()
            OSPrimaryButton(title: "Sure, I'll rate it") {
                Analytics.track(.ratingPromptShown)
                requestReview()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onNext() }
            }
            .padding(.horizontal, 24)
            Button("Maybe later") { onNext() }
                .font(OSFont.label(13))
                .foregroundStyle(OSColor.inkFaint)
                .padding(.bottom, 20)
        }
    }
}

struct CreatorCodeView: View {
    let onNext: (String?) -> Void
    @State private var code = ""

    var body: some View {
        VStack(spacing: 20) {
            OSDisplayText(text: "Did a creator send you?", size: 26)
                .padding(.top, 60)
            TextField("Creator code", text: $code)
                .textFieldStyle(.plain)
                .font(OSFont.stamp(20))
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(14)
                .background(OSColor.creamDim)
                .overlay(Rectangle().stroke(OSColor.ink.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 60)
            OSPrimaryButton(title: "Continue", enabled: !code.trimmingCharacters(in: .whitespaces).isEmpty) {
                onNext(code.trimmingCharacters(in: .whitespaces))
            }
            .padding(.horizontal, 24)
            Button("Skip") { onNext(nil) }
                .font(OSFont.label(15))
                .foregroundStyle(OSColor.inkFaint)
            Spacer()
        }
    }
}

// MARK: - Phase 3: Reveal

struct ComputingView: View {
    let onDone: () -> Void
    @State private var visibleLines = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lines = [
        "Analyzing your aesthetic",
        "Matching film stocks",
        "Calibrating grain",
        "Building your profile",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            ForEach(lines.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Image(systemName: index < visibleLines ? "checkmark.square.fill" : "square")
                        .foregroundStyle(index < visibleLines ? OSColor.accent : OSColor.inkFaint)
                    Text(lines[index])
                        .font(OSFont.body(17))
                        .foregroundStyle(OSColor.ink)
                }
                .opacity(index <= visibleLines ? 1 : 0.3)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { run() }
    }

    private func run() {
        if reduceMotion {
            visibleLines = lines.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone() }
            return
        }
        for i in 1...lines.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7) {
                visibleLines = i
                if i == lines.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone() }
                }
            }
        }
    }
}

/// The screenshottable identity card: profile name, matched cameras, sample
/// render, subtle wordmark. Share button renders the card to an image.
struct ProfileCardView: View {
    let profile: FilmProfile
    let onNext: () -> Void
    @State private var shareImage: UIImage?

    var body: some View {
        VStack(spacing: 22) {
            OSLabelText(text: "Your film profile", size: 12)
                .padding(.top, 28)

            card

            HStack(spacing: 14) {
                OSSecondaryButton(title: "Share") { share() }
                    .frame(width: 130)
                OSPrimaryButton(title: "Develop my first print") { onNext() }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .sheet(isPresented: Binding(get: { shareImage != nil },
                                    set: { if !$0 { shareImage = nil } })) {
            if let shareImage { ShareSheet(items: [shareImage]) }
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            OSDisplayText(text: profile.id, size: 38, color: OSColor.accent)
            Text(profile.tagline)
                .font(OSFont.body(14))
                .foregroundStyle(OSColor.inkFaint)
            Image(uiImage: SampleImageFactory.developed(camera: profile.primaryCamera))
                .resizable().scaledToFill()
                .frame(height: 220)
                .clipped()
            HStack(spacing: 12) {
                ForEach(profile.cameras) { camera in
                    let stock = FilmStockLibrary.stock(for: camera)
                    VStack(spacing: 4) {
                        CameraBodyView(stock: stock)
                            .frame(width: 72, height: 50)
                        OSLabelText(text: stock.displayName, size: 9, color: OSColor.ink)
                    }
                }
            }
            OSLabelText(text: "oldsnap", size: 10, color: OSColor.inkFaint.opacity(0.6))
        }
        .padding(20)
        .background(OSColor.creamDim)
        .overlay(Rectangle().stroke(OSColor.ink.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private func share() {
        let renderer = ImageRenderer(content: card.frame(width: 380).background(OSColor.cream))
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = image
        }
    }
}
