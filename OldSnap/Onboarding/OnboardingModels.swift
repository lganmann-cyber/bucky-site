import Foundation

/// Everything the intake flow learns, persisted locally (no accounts at v1).
/// Survives app kill mid-flow — the flow resumes at the first unanswered step.
struct OnboardingProfile: Codable {
    enum PhotosFeel: String, Codable, CaseIterable {
        case tooPerfect, flatBoring, likeEveryone, neverPost

        var label: String {
            switch self {
            case .tooPerfect: return "Too perfect"
            case .flatBoring: return "Flat and boring"
            case .likeEveryone: return "Like everyone else's"
            case .neverPost: return "I never post them"
            }
        }
    }

    enum FeedFeeling: String, Codable, CaseIterable {
        case nostalgic, jealous, inspired

        var label: String {
            switch self {
            case .nostalgic: return "Nostalgic"
            case .jealous: return "Jealous, honestly"
            case .inspired: return "Inspired"
            }
        }
    }

    enum FilmExperience: String, Codable, CaseIterable {
        case yesExpensive, alwaysWanted, no

        var label: String {
            switch self {
            case .yesExpensive: return "Yes, but it's expensive"
            case .alwaysWanted: return "Always wanted to"
            case .no: return "No"
            }
        }

        /// Tailored one-line response shown after the tap.
        var response: String {
            switch self {
            case .yesExpensive: return "A single developed roll runs about $25. Yours will cost nothing."
            case .alwaysWanted: return "You're about to shoot your first roll tonight."
            case .no: return "Perfect — no habits to unlearn."
            }
        }
    }

    /// Q7 — the four aesthetic tiles; the primary Film Profile signal.
    enum Aesthetic: String, Codable, CaseIterable {
        case flashParty   // 35C
        case fadedSummer  // SUN 200
        case y2kDigicam   // DC-2000
        case moodyNight   // 800T

        var label: String {
            switch self {
            case .flashParty: return "90s flash party"
            case .fadedSummer: return "Faded 70s summer"
            case .y2kDigicam: return "Y2K digicam"
            case .moodyNight: return "Moody night"
            }
        }

        var primaryCamera: CameraID {
            switch self {
            case .flashParty: return .c35
            case .fadedSummer: return .sun200
            case .y2kDigicam: return .dc2000
            case .moodyNight: return .t800
            }
        }
    }

    enum Destination: String, Codable, CaseIterable {
        case instagram, groupChats, justForMe

        var label: String {
            switch self {
            case .instagram: return "Instagram"
            case .groupChats: return "Group chats"
            case .justForMe: return "Just for me"
            }
        }
    }

    var photosFeel: PhotosFeel?
    var photoCount: Double = 12000
    var feedFeeling: FeedFeeling?
    var filmExperience: FilmExperience?
    var aesthetic: Aesthetic?
    var destination: Destination?
    var creatorCode: String?
    var generatedProfileName: String?
    var completed = false

    // MARK: Persistence

    private static let key = "os.onboarding.profile"

    static func load() -> OnboardingProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(OnboardingProfile.self, from: data)
        else { return OnboardingProfile() }
        return profile
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Film Profile matrix

/// A named identity generated from intake answers. 12 profiles cover the
/// combination space: 4 aesthetics × 3 mood variants. The mood variant is
/// picked from Q3 (how photos feel) and Q5 (feed feeling), so two friends
/// with the same tile choice can still land on different cards.
struct FilmProfile: Identifiable {
    let id: String            // e.g. "FLASH '96"
    let aesthetic: OnboardingProfile.Aesthetic
    let tagline: String
    let cameras: [CameraID]   // 3 matched, primary first

    var primaryCamera: CameraID { cameras[0] }
}

enum FilmProfileMatrix {
    /// All 12 profiles, three per aesthetic (indexes 0–2 = mood variants).
    static let matrix: [OnboardingProfile.Aesthetic: [FilmProfile]] = [
        .flashParty: [
            FilmProfile(id: "FLASH '96", aesthetic: .flashParty,
                        tagline: "Loud rooms, red eyes, no regrets.",
                        cameras: [.c35, .l79, .hf72]),
            FilmProfile(id: "HOUSE PARTY '93", aesthetic: .flashParty,
                        tagline: "The roll everyone begs copies of.",
                        cameras: [.c35, .sun200, .l79]),
            FilmProfile(id: "LAST DANCE '99", aesthetic: .flashParty,
                        tagline: "End-of-an-era energy, every night.",
                        cameras: [.c35, .t800, .dc2000]),
        ],
        .fadedSummer: [
            FilmProfile(id: "GOLDEN HOUR '94", aesthetic: .fadedSummer,
                        tagline: "Warm light, soft edges, long evenings.",
                        cameras: [.sun200, .c35, .p110]),
            FilmProfile(id: "POOLSIDE '77", aesthetic: .fadedSummer,
                        tagline: "Sun-bleached and perfectly unhurried.",
                        cameras: [.sun200, .sq70, .p110]),
            FilmProfile(id: "ROADTRIP '86", aesthetic: .fadedSummer,
                        tagline: "Windows down, horizon slightly crooked.",
                        cameras: [.sun200, .chrome64, .hf72]),
        ],
        .y2kDigicam: [
            FilmProfile(id: "POOLSIDE '02", aesthetic: .y2kDigicam,
                        tagline: "Blown highlights, zero irony.",
                        cameras: [.dc2000, .c35, .l79]),
            FilmProfile(id: "MALL GLOW '01", aesthetic: .y2kDigicam,
                        tagline: "Fluorescent light was your golden hour.",
                        cameras: [.dc2000, .hf72, .sun200]),
            FilmProfile(id: "BURN CD '03", aesthetic: .y2kDigicam,
                        tagline: "Every night out, archived in 3 megapixels.",
                        cameras: [.dc2000, .t800, .c35]),
        ],
        .moodyNight: [
            FilmProfile(id: "MIDNIGHT '82", aesthetic: .moodyNight,
                        tagline: "The city hums; you notice.",
                        cameras: [.t800, .mono400, .c35]),
            FilmProfile(id: "NEON RAIN '89", aesthetic: .moodyNight,
                        tagline: "Wet streets, warm signs, cold air.",
                        cameras: [.t800, .dc2000, .l79]),
            FilmProfile(id: "DARKROOM '77", aesthetic: .moodyNight,
                        tagline: "Quiet, deliberate, permanent.",
                        cameras: [.t800, .mono400, .chrome64]),
        ],
    ]

    /// Deterministic generation: aesthetic picks the row, Q3+Q5 pick the
    /// variant, so the same answers always produce the same card.
    static func profile(for answers: OnboardingProfile) -> FilmProfile {
        let aesthetic = answers.aesthetic ?? .flashParty
        let variants = matrix[aesthetic] ?? []
        let feelIndex = OnboardingProfile.PhotosFeel.allCases.firstIndex(of: answers.photosFeel ?? .tooPerfect) ?? 0
        let feedIndex = OnboardingProfile.FeedFeeling.allCases.firstIndex(of: answers.feedFeeling ?? .nostalgic) ?? 0
        let variant = (feelIndex + feedIndex) % max(variants.count, 1)
        return variants[variant]
    }
}
