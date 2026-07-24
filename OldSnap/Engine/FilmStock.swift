import Foundation
import CoreGraphics

/// Stable identifiers for the ten launch cameras. Raw values appear in
/// analytics and on-disk metadata, so they never change.
enum CameraID: String, Codable, CaseIterable, Identifiable {
    case c35 = "35C"
    case sun200 = "SUN200"
    case sq70 = "SQ70"
    case chrome64 = "CHROME64"
    case t800 = "800T"
    case dc2000 = "DC2000"
    case mono400 = "MONO400"
    case l79 = "L79"
    case hf72 = "HF72"
    case p110 = "P110"

    var id: String { rawValue }
}

/// A plain RGB triple used by the color model (0...1, linear-ish working space).
struct RGB: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    static let neutral = RGB(r: 0, g: 0, b: 0)
}

/// Full color response of a stock. Everything here is baked into one cached
/// 3D LUT (33³ color cube) per stock, so the whole model costs a single
/// CIColorCube at render time.
struct ColorScience: Codable {
    /// Warm(+)/cool(−) white balance shift, roughly ±1 = ±heavy cast.
    var temperature: Double = 0
    /// Magenta(+)/green(−) tint shift.
    var tint: Double = 0

    /// Per-channel tone curves as five control points (inputs 0, .25, .5, .75, 1).
    /// These carry the stock's contrast character and channel crosstalk.
    var curveR: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var curveG: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var curveB: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var saturation: Double = 1
    /// Extra saturation applied preferentially to already-muted colors.
    var vibrance: Double = 0

    /// Color cast injected into shadows / highlights (strength folded into RGB).
    var shadowTint: RGB = .neutral
    var highlightTint: RGB = .neutral

    /// Lifted blacks (film fade / print base). 0.06 ≈ visible milky blacks.
    var blackLift: Double = 0
    /// Soft highlight compression; 0 = clip like digital, 1 = long film shoulder.
    var highlightRolloff: Double = 0.5

    /// Global gamma trim applied before the curves.
    var gamma: Double = 1

    /// Full desaturation for monochrome stocks (applied before grain so grain
    /// stays luma-only naturally).
    var monochrome: Bool = false
}

/// Procedural grain description. Size is in units of *thousandths of the long
/// image edge*, never fixed pixels, so a 12 MP export and a 1 MP preview show
/// the same grain character.
struct GrainParams: Codable {
    var intensity: Double = 0      // 0 = none, 0.35 = disposable-camera heavy
    var size: Double = 1.6         // grain clump size, ‰ of long edge
    var chromaMix: Double = 0.1    // 0 = pure luma grain, 1 = full color noise
    var shadowWeight: Double = 0.6 // how much grain concentrates in shadows/mids
}

struct HalationParams: Codable {
    var threshold: Double = 0.8    // luminance above which halation blooms
    var radius: Double = 18        // ‰ of long edge
    var tint: RGB = RGB(r: 1, g: 0.35, b: 0.15) // red-orange for cine film
    var intensity: Double = 0.5
}

struct VignetteParams: Codable {
    var strength: Double = 0       // 0...2
    var radius: Double = 1.6       // falloff start, larger = subtler
}

/// Frame treatments applied after the image pipeline.
enum FrameStyle: String, Codable {
    case none
    case instantWhite      // classic instant print border, thick chin
    case halfFrameDiptych  // two shots in one 35mm frame with center gutter
}

/// Probability table for per-shot randomized artifacts. Sampled with the
/// stored seed so re-renders are stable.
struct ArtifactTable: Codable {
    var lightLeakChance: Double = 0
    var lightLeakStrength: Double = 0.5
    var dustChance: Double = 0
    /// Simulates a harsh onboard flash: hot center, falloff to dark edges.
    var flashFalloff: Double = 0
    /// Purple-magenta fringing on hard highlight edges (CCD digicams).
    var purpleFringe: Double = 0
}

/// Shot-to-shot variance ranges. Real film never renders twice the same.
struct VarianceParams: Codable {
    var exposureJitter: Double = 0.06  // ± EV-ish jitter
    var temperatureJitter: Double = 0.03
    var grainJitter: Double = 0.15     // relative grain intensity wobble
}

/// One camera = one fully parametric film look. No baked textures anywhere:
/// every field feeds the procedural pipeline in `FilmEngine`.
struct FilmStock: Identifiable {
    let id: CameraID
    let displayName: String
    let eraTag: String
    let tagline: String

    var color = ColorScience()
    var grain = GrainParams()
    var halation: HalationParams? = nil
    /// Soft glow / lens softness (‰ of long edge blur mixed back in).
    var bloom: Double = 0
    var vignette = VignetteParams()
    /// Radial chromatic aberration strength at edges (0...1).
    var chromaticAberration: Double = 0
    /// If set, the image is downsampled to this fraction of source resolution
    /// and upsampled back — the small-sensor / tiny-negative "crunch".
    var resolutionCrush: Double? = nil
    var sharpen: Double = 0
    var frame: FrameStyle = .none
    var dateStampDefault: Bool = false
    var artifacts = ArtifactTable()
    var variance = VarianceParams()

    /// Body color used by the rendered skeuomorphic camera in the picker.
    var bodyStyle: CameraBodyStyle = .init()
}

/// Minimal art direction for the procedurally drawn camera bodies in the
/// picker shelf (no photo assets at v1).
struct CameraBodyStyle {
    var bodyHex: UInt32 = 0x30302C
    var plateHex: UInt32 = 0xD8D2C2
    var accentHex: UInt32 = 0xC75B39
    /// Rough silhouette family the picker draws.
    var shape: Shape = .compact35

    enum Shape { case compact35, instantBox, slr, digicam, pocket110, toy }
}
