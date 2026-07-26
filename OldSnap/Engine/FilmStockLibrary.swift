import Foundation

/// The ten launch cameras. Every number here traces back to observations in
/// `Engine/Calibration/<camera>.md` — tweak there first, then here, then
/// verify in the debug comparison grid (Settings → Developer → Preset Grid).
enum FilmStockLibrary {
    static func stock(for id: CameraID) -> FilmStock {
        all.first { $0.id == id } ?? all[0]
    }

    /// Order matters: this is the shelf order in the camera picker.
    static let all: [FilmStock] = [
        c35, sun200, sq70, chrome64, t800, dc2000, mono400, l79, hf72, p110,
    ]

    // MARK: 1 · 35C — '90s single-use disposable. The hero camera.
    // Calibration: consumer 800-speed color neg behind a plastic meniscus
    // lens with a harsh onboard flash. See Calibration/35C.md.
    static let c35: FilmStock = {
        var s = FilmStock(id: .c35, displayName: "35C", eraTag: "'90s",
                          tagline: "Every party in 1996 is on one of these.")
        s.color.temperature = 0.30
        s.color.gamma = 1.04
        // High-contrast consumer neg: crushed toe, fast shoulder.
        s.color.curveR = [0.01, 0.24, 0.55, 0.82, 1.0]
        s.color.curveG = [0.00, 0.21, 0.51, 0.78, 0.99]
        s.color.curveB = [0.00, 0.19, 0.47, 0.74, 0.96]
        s.color.saturation = 1.08
        s.color.vibrance = 0.10
        s.color.shadowTint = RGB(r: 0.015, g: 0.005, b: -0.01) // warm-brown shadows
        s.color.highlightTint = RGB(r: 0.03, g: 0.015, b: 0)   // flash-warm highlights
        s.color.blackLift = 0.02
        s.color.highlightRolloff = 0.65
        s.grain = GrainParams(intensity: 0.22, size: 0.8, chromaMix: 0.18, shadowWeight: 0.70)
        s.bloom = 1.2
        s.vignette = VignetteParams(strength: 0.9, radius: 1.5)
        s.chromaticAberration = 0.35
        s.sharpen = 0.15
        s.dateStampDefault = true
        s.artifacts.flashFalloff = 0.65
        s.artifacts.dustChance = 0.15
        s.variance = VarianceParams(exposureJitter: 0.14, temperatureJitter: 0.05, grainJitter: 0.2)
        s.bodyStyle = .init(bodyHex: 0xE8B93B, plateHex: 0x2B2A26, accentHex: 0xC7392E, shape: .compact35)
        return s
    }()

    // MARK: 2 · SUN 200 — '90s consumer 200-speed color neg.
    // "Everything looks like childhood": golden warmth, forgiving skin.
    static let sun200: FilmStock = {
        var s = FilmStock(id: .sun200, displayName: "SUN 200", eraTag: "'90s",
                          tagline: "The film your childhood was shot on.")
        s.color.temperature = 0.38
        s.color.tint = 0.06
        // Gentle contrast, warm mids; red channel lifted through skin range.
        s.color.curveR = [0.02, 0.28, 0.55, 0.79, 0.99]
        s.color.curveG = [0.01, 0.26, 0.52, 0.76, 0.98]
        s.color.curveB = [0.01, 0.23, 0.47, 0.72, 0.95]
        s.color.saturation = 1.02
        s.color.vibrance = 0.14
        s.color.shadowTint = RGB(r: 0.01, g: 0.008, b: -0.008)
        s.color.highlightTint = RGB(r: 0.035, g: 0.025, b: 0) // golden highlights
        s.color.blackLift = 0.035
        s.color.highlightRolloff = 0.8
        s.grain = GrainParams(intensity: 0.10, size: 0.5, chromaMix: 0.12, shadowWeight: 0.6)
        s.bloom = 0.8
        s.vignette = VignetteParams(strength: 0.35, radius: 1.8)
        s.chromaticAberration = 0.12
        s.variance = VarianceParams(exposureJitter: 0.08, temperatureJitter: 0.04, grainJitter: 0.15)
        s.bodyStyle = .init(bodyHex: 0xD8D2C2, plateHex: 0x8C6E3C, accentHex: 0xC75B39, shape: .compact35)
        return s
    }()

    // MARK: 3 · SQ-70 — '70s white-frame instant.
    // Milky blacks, cyan-drifted shadows, cream highlights, soft lens.
    static let sq70: FilmStock = {
        var s = FilmStock(id: .sq70, displayName: "SQ-70", eraTag: "'70s",
                          tagline: "Shake it. (Don't actually shake it.)")
        s.color.temperature = 0.12
        s.color.gamma = 0.96
        // Compressed range top and bottom — dye prints never reach true black.
        s.color.curveR = [0.06, 0.28, 0.52, 0.76, 0.94]
        s.color.curveG = [0.06, 0.27, 0.51, 0.74, 0.93]
        s.color.curveB = [0.08, 0.28, 0.50, 0.72, 0.90]
        s.color.saturation = 0.86
        s.color.shadowTint = RGB(r: -0.015, g: 0.012, b: 0.028) // cyan-teal shadow drift
        s.color.highlightTint = RGB(r: 0.03, g: 0.022, b: 0.005) // cream highlights
        s.color.blackLift = 0.10
        s.color.highlightRolloff = 0.9
        s.grain = GrainParams(intensity: 0.06, size: 0.9, chromaMix: 0.25, shadowWeight: 0.4)
        s.bloom = 2.2
        s.vignette = VignetteParams(strength: 0.5, radius: 1.7)
        s.frame = .instantWhite
        s.artifacts.dustChance = 0.1
        s.variance = VarianceParams(exposureJitter: 0.16, temperatureJitter: 0.08, grainJitter: 0.1)
        s.bodyStyle = .init(bodyHex: 0xEFEAE0, plateHex: 0x3A3833, accentHex: 0xC7392E, shape: .instantBox)
        return s
    }()

    // MARK: 4 · CHROME 64 — '60s–'70s slide film. National Geographic 1971.
    // Saturated reds, inky shadows, fine grain, high micro-contrast.
    static let chrome64: FilmStock = {
        var s = FilmStock(id: .chrome64, displayName: "CHROME 64", eraTag: "'60s–'70s",
                          tagline: "The whole 20th century was archived on this.")
        s.color.temperature = 0.10
        s.color.gamma = 1.06
        // Slide-film contrast: deep toe, steep mids, hard-ish shoulder.
        s.color.curveR = [0.0, 0.22, 0.55, 0.83, 1.0]
        s.color.curveG = [0.0, 0.19, 0.50, 0.79, 0.99]
        s.color.curveB = [0.0, 0.18, 0.48, 0.77, 0.98]
        s.color.saturation = 1.16
        s.color.vibrance = 0.08
        s.color.shadowTint = RGB(r: 0.004, g: 0, b: 0.006) // barely-blue blacks
        s.color.highlightTint = RGB(r: 0.02, g: 0.008, b: -0.004)
        s.color.blackLift = 0.0
        s.color.highlightRolloff = 0.35 // slides clip harder than neg
        s.grain = GrainParams(intensity: 0.07, size: 0.4, chromaMix: 0.05, shadowWeight: 0.5)
        s.vignette = VignetteParams(strength: 0.25, radius: 1.9)
        s.sharpen = 0.35
        s.variance = VarianceParams(exposureJitter: 0.06, temperatureJitter: 0.02, grainJitter: 0.1)
        s.bodyStyle = .init(bodyHex: 0x1F1E1B, plateHex: 0xC9C3B4, accentHex: 0xB03A2E, shape: .slr)
        return s
    }()

    // MARK: 5 · 800T — tungsten cine film at night. The most shared look.
    // Red-orange halation around lights, teal shadows, warm point sources.
    static let t800: FilmStock = {
        var s = FilmStock(id: .t800, displayName: "800T", eraTag: "Night",
                          tagline: "Streetlights were never just white.")
        s.color.temperature = -0.28 // tungsten balance cools daylight/LED scenes
        s.color.tint = -0.04
        s.color.curveR = [0.01, 0.24, 0.52, 0.79, 1.0]
        s.color.curveG = [0.02, 0.24, 0.51, 0.77, 0.98]
        s.color.curveB = [0.04, 0.27, 0.53, 0.78, 0.97]
        s.color.saturation = 1.04
        s.color.shadowTint = RGB(r: -0.02, g: 0.012, b: 0.032) // signature teal shadows
        s.color.highlightTint = RGB(r: 0.04, g: 0.02, b: -0.01) // warm practicals
        s.color.blackLift = 0.045
        s.color.highlightRolloff = 0.75
        s.grain = GrainParams(intensity: 0.15, size: 0.65, chromaMix: 0.2, shadowWeight: 0.65)
        s.halation = HalationParams(threshold: 0.72, radius: 22,
                                    tint: RGB(r: 1.0, g: 0.30, b: 0.10), intensity: 0.85)
        s.bloom = 1.0
        s.vignette = VignetteParams(strength: 0.4, radius: 1.7)
        s.variance = VarianceParams(exposureJitter: 0.10, temperatureJitter: 0.05, grainJitter: 0.2)
        s.bodyStyle = .init(bodyHex: 0x23272B, plateHex: 0xB8BEC4, accentHex: 0xC75B39, shape: .slr)
        return s
    }()

    // MARK: 6 · DC-2000 — early-2000s CCD digicam. Y2K crunch.
    // CCD color, clipped highlights, purple fringe, oversharpened low-res.
    static let dc2000: FilmStock = {
        var s = FilmStock(id: .dc2000, displayName: "DC-2000", eraTag: "'00s",
                          tagline: "3.2 megapixels of pure Y2K.")
        s.color.temperature = -0.06
        s.color.tint = 0.05 // CCD magenta bias
        s.color.curveR = [0.0, 0.24, 0.54, 0.81, 1.0]
        s.color.curveG = [0.0, 0.23, 0.53, 0.80, 1.0]
        s.color.curveB = [0.0, 0.25, 0.55, 0.82, 1.0]
        s.color.saturation = 1.18
        s.color.highlightRolloff = 0.05 // digital clip — highlights just die
        s.color.blackLift = 0.01
        // CCD shadow noise is chroma-heavy and fine-grained.
        s.grain = GrainParams(intensity: 0.09, size: 0.35, chromaMix: 0.7, shadowWeight: 0.9)
        s.chromaticAberration = 0.6
        s.resolutionCrush = 0.42
        s.sharpen = 0.7 // in-camera oversharpening halos
        s.dateStampDefault = true
        s.artifacts.flashFalloff = 0.45
        s.artifacts.purpleFringe = 0.8
        s.variance = VarianceParams(exposureJitter: 0.07, temperatureJitter: 0.06, grainJitter: 0.15)
        s.bodyStyle = .init(bodyHex: 0xB8BEC4, plateHex: 0x2B2A26, accentHex: 0x3E6FA8, shape: .digicam)
        return s
    }()

    // MARK: 7 · MONO 400 — timeless 400-speed B&W press film.
    // Punchy contrast, big honest grain, deep blacks.
    static let mono400: FilmStock = {
        var s = FilmStock(id: .mono400, displayName: "MONO 400", eraTag: "Timeless",
                          tagline: "Every photo you've ever seen in a museum.")
        s.color.monochrome = true
        s.color.gamma = 1.05
        let punch: [Double] = [0.0, 0.19, 0.50, 0.81, 1.0]
        s.color.curveR = punch; s.color.curveG = punch; s.color.curveB = punch
        s.color.blackLift = 0.0
        s.color.highlightRolloff = 0.85
        s.grain = GrainParams(intensity: 0.18, size: 0.7, chromaMix: 0.0, shadowWeight: 0.55)
        s.vignette = VignetteParams(strength: 0.35, radius: 1.8)
        s.sharpen = 0.2
        s.variance = VarianceParams(exposureJitter: 0.10, temperatureJitter: 0, grainJitter: 0.2)
        s.bodyStyle = .init(bodyHex: 0x2B2A26, plateHex: 0xC9C3B4, accentHex: 0x6B675E, shape: .slr)
        return s
    }()

    // MARK: 8 · L-79 — '70s plastic toy camera. Chaos by design.
    // Light leaks, heavy vignette, unpredictable saturation. Highest variance.
    static let l79: FilmStock = {
        var s = FilmStock(id: .l79, displayName: "L-79", eraTag: "'70s",
                          tagline: "A $12 camera that shoots like a mood.")
        s.color.temperature = 0.18
        s.color.curveR = [0.02, 0.26, 0.55, 0.80, 0.98]
        s.color.curveG = [0.0, 0.22, 0.52, 0.78, 0.99]
        s.color.curveB = [0.01, 0.20, 0.46, 0.72, 0.95]
        s.color.saturation = 1.24
        s.color.vibrance = 0.1
        s.color.shadowTint = RGB(r: 0.01, g: 0.01, b: -0.01)
        s.color.blackLift = 0.03
        s.color.highlightRolloff = 0.6
        s.grain = GrainParams(intensity: 0.13, size: 0.7, chromaMix: 0.2, shadowWeight: 0.6)
        s.bloom = 1.8 // plastic meniscus lens
        s.vignette = VignetteParams(strength: 1.6, radius: 1.25)
        s.chromaticAberration = 0.45
        s.artifacts.lightLeakChance = 0.6
        s.artifacts.lightLeakStrength = 0.7
        s.artifacts.dustChance = 0.25
        // The biggest shot-to-shot swing in the lineup — that's the camera.
        s.variance = VarianceParams(exposureJitter: 0.28, temperatureJitter: 0.10, grainJitter: 0.3)
        s.bodyStyle = .init(bodyHex: 0x35507A, plateHex: 0x2B2A26, accentHex: 0xC7392E, shape: .toy)
        return s
    }()

    // MARK: 9 · HF-72 — '80s half-frame 35mm. 72 shots per roll, diptychs.
    // Consumer neg pushed through a tiny frame: more grain, gentle colors.
    static let hf72: FilmStock = {
        var s = FilmStock(id: .hf72, displayName: "HF-72", eraTag: "'80s",
                          tagline: "Two memories per frame. 72 per roll.")
        s.color.temperature = 0.22
        s.color.curveR = [0.01, 0.25, 0.52, 0.77, 0.98]
        s.color.curveG = [0.01, 0.24, 0.51, 0.76, 0.97]
        s.color.curveB = [0.01, 0.22, 0.48, 0.73, 0.95]
        s.color.saturation = 0.98
        s.color.vibrance = 0.08
        s.color.highlightTint = RGB(r: 0.02, g: 0.014, b: 0)
        s.color.blackLift = 0.03
        s.color.highlightRolloff = 0.7
        // Half the negative area → grain reads ~40% larger than full frame.
        s.grain = GrainParams(intensity: 0.16, size: 0.75, chromaMix: 0.15, shadowWeight: 0.6)
        s.bloom = 1.0
        s.vignette = VignetteParams(strength: 0.5, radius: 1.6)
        s.frame = .halfFrameDiptych
        s.variance = VarianceParams(exposureJitter: 0.12, temperatureJitter: 0.05, grainJitter: 0.2)
        s.bodyStyle = .init(bodyHex: 0xC9C3B4, plateHex: 0x2B2A26, accentHex: 0xC75B39, shape: .compact35)
        return s
    }()

    // MARK: 10 · P110 — '70s–'80s pocket 110 cartridge.
    // Tiny negative: soft, extra grainy, muted, a hint of motion softness.
    static let p110: FilmStock = {
        var s = FilmStock(id: .p110, displayName: "P110", eraTag: "'70s–'80s",
                          tagline: "Fits in a jacket pocket. Softens every memory.")
        s.color.temperature = 0.15
        s.color.gamma = 0.98
        s.color.curveR = [0.03, 0.26, 0.51, 0.75, 0.96]
        s.color.curveG = [0.03, 0.25, 0.50, 0.74, 0.95]
        s.color.curveB = [0.03, 0.23, 0.47, 0.71, 0.93]
        s.color.saturation = 0.82
        s.color.shadowTint = RGB(r: 0.008, g: 0.006, b: 0)
        s.color.blackLift = 0.05
        s.color.highlightRolloff = 0.8
        s.grain = GrainParams(intensity: 0.20, size: 0.95, chromaMix: 0.22, shadowWeight: 0.55)
        s.bloom = 2.4 // fixed-focus lens + hand shake on a light body
        s.vignette = VignetteParams(strength: 0.6, radius: 1.6)
        s.resolutionCrush = 0.6
        s.variance = VarianceParams(exposureJitter: 0.16, temperatureJitter: 0.07, grainJitter: 0.25)
        s.bodyStyle = .init(bodyHex: 0x4A4640, plateHex: 0xD8D2C2, accentHex: 0xC75B39, shape: .pocket110)
        return s
    }()
}
