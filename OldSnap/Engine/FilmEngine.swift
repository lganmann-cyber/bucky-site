import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The single parametric render pipeline. Every camera is just a `FilmStock`
/// fed through here; there are no per-camera code paths and no baked overlay
/// textures. Grain and halation are procedural (Metal kernel when available,
/// pure Core Image otherwise).
///
/// Pipeline order (matches how the physical system works):
///   resolution crunch → exposure jitter → color science (one cached 3D LUT)
///   → bloom → halation → chromatic aberration → grain → vignette
///   → flash falloff / light leaks → frame treatment (CG pass).
final class FilmEngine {
    static let shared = FilmEngine()

    enum Quality {
        case preview  // live viewfinder: fewer taps, smaller radii
        case full     // develop: everything on, full resolution
    }

    enum DateStampMode: Codable, Equatable {
        case off
        /// Random plausible 90s date derived from the shot seed (default).
        case retroRandom
        /// The user asked for the real capture date.
        case actual(Date)
    }

    struct RenderOptions {
        var seed: UInt64
        var quality: Quality = .full
        var dateStamp: DateStampMode = .off
        var watermark: Bool = false
    }

    private let context: CIContext
    private var cubeCache: [CameraID: Data] = [:]
    private let cubeDimension = 33
    private var grainKernel: CIColorKernel?
    private let cacheLock = NSLock()

    private init() {
        // cacheIntermediates off keeps bulk develops memory-flat.
        context = CIContext(options: [
            .cacheIntermediates: false,
            .name: "OldSnapFilmEngine",
        ])
        grainKernel = Self.loadGrainKernel()
    }

    /// Stitchable CI kernels live in the default metallib. If loading fails
    /// (simulator quirks, toolchain differences) the engine silently uses the
    /// Core Image procedural fallback — output differs only microscopically.
    private static func loadGrainKernel() -> CIColorKernel? {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "osGrain", fromMetalLibraryData: data)
    }

    // MARK: - Public entry points

    /// Renders a full-quality develop and returns encodable image data.
    /// Runs the CI graph inside an autoreleasepool so 36-photo batches stay
    /// memory-safe.
    func developJPEG(source: UIImage, stock: FilmStock, options: RenderOptions,
                     compressionQuality: CGFloat = 0.92) -> Data? {
        autoreleasepool {
            guard let rendered = developUIImage(source: source, stock: stock, options: options) else { return nil }
            return rendered.jpegData(compressionQuality: compressionQuality)
        }
    }

    func developHEIC(source: UIImage, stock: FilmStock, options: RenderOptions) -> Data? {
        autoreleasepool {
            guard let rendered = developUIImage(source: source, stock: stock, options: options),
                  let cg = rendered.cgImage else { return nil }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data, "public.heic" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return data as Data
        }
    }

    func developUIImage(source: UIImage, stock: FilmStock, options: RenderOptions) -> UIImage? {
        guard let normalized = source.osNormalizedUp(), let cgSource = normalized.cgImage else { return nil }
        let input = CIImage(cgImage: cgSource)
        let graph = apply(stock: stock, to: input, options: options)
        guard let cgOut = context.createCGImage(graph, from: graph.extent) else { return nil }
        // Frame treatment + stamps happen in a CG pass at full resolution.
        return FrameRenderer.compose(image: cgOut, stock: stock, options: options)
    }

    /// Combines two developed half-frames into one 35mm diptych (HF-72).
    func composeDiptych(left: UIImage, right: UIImage) -> UIImage? {
        FrameRenderer.diptych(left: left, right: right)
    }

    /// Live viewfinder path: takes a camera frame, returns a filtered CIImage.
    /// Callers render via their own MTKView/CIContext.
    func previewImage(for input: CIImage, stock: FilmStock, seed: UInt64) -> CIImage {
        apply(stock: stock, to: input,
              options: RenderOptions(seed: seed, quality: .preview))
    }

    // MARK: - The pipeline

    func apply(stock: FilmStock, to input: CIImage, options: RenderOptions) -> CIImage {
        var rng = SeededRandom(seed: options.seed)
        let extent = input.extent
        let longEdge = max(extent.width, extent.height)
        var image = input

        // Per-shot variance, sampled deterministically from the seed.
        let exposureJitter = rng.uniform(-stock.variance.exposureJitter...stock.variance.exposureJitter)
        let tempJitter = rng.uniform(-stock.variance.temperatureJitter...stock.variance.temperatureJitter)
        let grainScale = 1 + rng.uniform(-stock.variance.grainJitter...stock.variance.grainJitter)

        // 1. Resolution crunch (small sensors / tiny negatives).
        if let crush = stock.resolutionCrush, crush < 1, options.quality == .full {
            image = image.osResampled(scale: crush).osResampled(scale: 1 / crush)
                .cropped(to: extent)
        }

        // 2. Exposure jitter — real film never meters twice the same.
        if abs(exposureJitter) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposureJitter])
        }

        // 3. Full color science in one cached 3D LUT.
        image = applyColorCube(to: image, stock: stock)

        // Jittered white-balance wobble on top of the baked cast.
        if abs(tempJitter) > 0.001 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - CGFloat(tempJitter) * 3000, y: 0),
            ])
        }

        // 4. Bloom / lens softness.
        if stock.bloom > 0 {
            let radius = permilToPixels(stock.bloom, longEdge: longEdge, quality: options.quality)
            let blurred = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
            image = blurred.osScaledAlpha(0.35).composited(over: image)
        }

        // 5. Halation — highlights bleeding through the emulsion, tinted by
        // the anti-halation layer (or its absence).
        if let hal = stock.halation {
            image = applyHalation(to: image, params: hal, longEdge: longEdge, quality: options.quality)
        }

        // 6. Chromatic aberration / purple fringing at the edges.
        if stock.chromaticAberration > 0.001 {
            image = applyChromaticAberration(to: image, strength: stock.chromaticAberration,
                                             purple: stock.artifacts.purpleFringe, extent: extent)
        }

        // 7. Procedural grain.
        if stock.grain.intensity > 0.001 {
            var g = stock.grain
            g.intensity *= grainScale
            image = applyGrain(to: image, params: g, seed: options.seed,
                               longEdge: longEdge, quality: options.quality)
        }

        // 8. Vignette.
        if stock.vignette.strength > 0.001 {
            image = image.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: max(extent.width, extent.height) * stock.vignette.radius * 0.5,
                kCIInputIntensityKey: stock.vignette.strength,
            ])
        }

        // 9. Flash falloff: hot center, edges dropping to black — the
        // disposable-camera-at-a-party signature.
        if stock.artifacts.flashFalloff > 0.001 {
            image = applyFlashFalloff(to: image, strength: stock.artifacts.flashFalloff,
                                      extent: extent, rng: &rng)
        }

        // 10. Light leaks — positioned variants, random per shot.
        if options.quality == .full, rng.chance(stock.artifacts.lightLeakChance) {
            image = applyLightLeak(to: image, strength: stock.artifacts.lightLeakStrength,
                                   extent: extent, rng: &rng)
        }

        // 11. Output sharpen (scanner sharpening on lab scans).
        if stock.sharpen > 0.001, options.quality == .full {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: stock.sharpen,
            ])
        }

        return image.cropped(to: extent)
    }

    // MARK: - Color science

    /// The entire `ColorScience` model baked into a 33³ cube, cached per stock.
    private func applyColorCube(to image: CIImage, stock: FilmStock) -> CIImage {
        let data = cubeData(for: stock)
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeDimension,
            "inputCubeData": data,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
    }

    private func cubeData(for stock: FilmStock) -> Data {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cubeCache[stock.id] { return cached }

        let n = cubeDimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        let c = stock.color
        var offset = 0
        for bi in 0..<n {
            let b0 = Double(bi) / Double(n - 1)
            for gi in 0..<n {
                let g0 = Double(gi) / Double(n - 1)
                for ri in 0..<n {
                    let r0 = Double(ri) / Double(n - 1)
                    let out = Self.transform(r: r0, g: g0, b: b0, science: c)
                    cube[offset] = Float(out.r); cube[offset + 1] = Float(out.g)
                    cube[offset + 2] = Float(out.b); cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        cubeCache[stock.id] = data
        return data
    }

    /// The color model itself — deliberately explicit so calibration notes in
    /// Engine/Calibration map one-to-one onto code.
    static func transform(r rIn: Double, g gIn: Double, b bIn: Double, science c: ColorScience) -> RGB {
        var r = rIn, g = gIn, b = bIn

        // Gamma trim (overall density).
        if c.gamma != 1 {
            r = pow(r, c.gamma); g = pow(g, c.gamma); b = pow(b, c.gamma)
        }

        // White balance cast via channel gains.
        r *= 1 + 0.22 * c.temperature
        b *= 1 - 0.22 * c.temperature
        g *= 1 - 0.12 * c.tint

        // Per-channel characteristic curves.
        r = Self.curve(r, points: c.curveR)
        g = Self.curve(g, points: c.curveG)
        b = Self.curve(b, points: c.curveB)

        var luma = 0.299 * r + 0.587 * g + 0.114 * b

        if c.monochrome {
            r = luma; g = luma; b = luma
        } else {
            // Saturation + vibrance (vibrance boosts muted colors harder).
            let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
            let currentSat = maxC <= 0.0001 ? 0 : (maxC - minC) / maxC
            let satFactor = c.saturation + c.vibrance * (1 - currentSat)
            r = luma + (r - luma) * satFactor
            g = luma + (g - luma) * satFactor
            b = luma + (b - luma) * satFactor
        }

        // Split toning: casts injected by luminance zone.
        luma = min(max(0.299 * r + 0.587 * g + 0.114 * b, 0), 1)
        let shadowW = pow(1 - luma, 2)
        let highlightW = pow(luma, 2)
        r += c.shadowTint.r * shadowW + c.highlightTint.r * highlightW
        g += c.shadowTint.g * shadowW + c.highlightTint.g * highlightW
        b += c.shadowTint.b * shadowW + c.highlightTint.b * highlightW

        // Film shoulder: soft highlight compression instead of digital clip.
        if c.highlightRolloff > 0 {
            let knee = 1 - 0.35 * c.highlightRolloff
            func shoulder(_ v: Double) -> Double {
                guard v > knee else { return v }
                let span = 1 - knee
                return knee + span * tanh((v - knee) / span)
            }
            r = shoulder(r); g = shoulder(g); b = shoulder(b)
        }

        // Lifted blacks (print base / fade).
        if c.blackLift > 0 {
            r = c.blackLift + r * (1 - c.blackLift)
            g = c.blackLift + g * (1 - c.blackLift)
            b = c.blackLift + b * (1 - c.blackLift)
        }

        return RGB(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1))
    }

    /// Catmull-Rom interpolation through five control points at x = 0, .25, .5, .75, 1.
    static func curve(_ x: Double, points p: [Double]) -> Double {
        guard p.count == 5 else { return x }
        let clamped = min(max(x, 0), 1)
        let scaled = clamped * 4
        let i = min(Int(scaled), 3)
        let t = scaled - Double(i)
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, 4)]
        let t2 = t * t, t3 = t2 * t
        let v = 0.5 * ((2 * p1) + (-p0 + p2) * t
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        return min(max(v, 0), 1)
    }

    // MARK: - Halation

    private func applyHalation(to image: CIImage, params: HalationParams,
                               longEdge: CGFloat, quality: Quality) -> CIImage {
        let extent = image.extent
        // Soft-extract highlights above the threshold.
        let scale = 1.0 / max(1 - params.threshold, 0.05)
        let highlights = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0),
            "inputBiasVector": CIVector(x: CGFloat(-params.threshold * scale),
                                        y: CGFloat(-params.threshold * scale),
                                        z: CGFloat(-params.threshold * scale), w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])

        let radius = permilToPixels(params.radius, longEdge: longEdge, quality: quality)
        let glow = highlights.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(params.tint.r * params.intensity), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(params.tint.g * params.intensity), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(params.tint.b * params.intensity), w: 0),
            ])
        return glow.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
    }

    // MARK: - Chromatic aberration

    /// Radial CA: red channel scaled outward, blue inward, masked so the
    /// center stays clean. `purple` shifts the fringe toward magenta (CCD look).
    private func applyChromaticAberration(to image: CIImage, strength: Double,
                                          purple: Double, extent: CGRect) -> CIImage {
        let shift = 1 + 0.0035 * strength
        let center = CGPoint(x: extent.midX, y: extent.midY)

        func scaled(_ img: CIImage, by factor: CGFloat) -> CIImage {
            let t = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: factor, y: factor)
                .translatedBy(x: -center.x, y: -center.y)
            return img.transformed(by: t).cropped(to: extent)
        }

        let red = image.osChannel(r: 1, g: 0, b: 0)
        let green = image.osChannel(r: 0, g: 1, b: 0)
        let blue = image.osChannel(r: 0, g: 0, b: 1)
        let redOut = scaled(red, by: CGFloat(shift))
        let blueOut = scaled(blue, by: CGFloat(2 - shift))
        var fringed = redOut
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blueOut])

        if purple > 0.001 {
            // Nudge the displaced red toward magenta for CCD-style fringing.
            fringed = fringed.applyingFilter("CIColorMatrix", parameters: [
                "inputBVector": CIVector(x: CGFloat(0.06 * purple), y: 0, z: 1, w: 0),
            ])
        }

        // Radial mask: 0 at center, 1 at corners → fringing only at edges.
        let radius = max(extent.width, extent.height)
        let mask = CIFilter.radialGradient()
        mask.center = center
        mask.radius0 = Float(radius * 0.35)
        mask.radius1 = Float(radius * 0.72)
        mask.color0 = CIColor.black
        mask.color1 = CIColor.white
        let maskImage = (mask.outputImage ?? CIImage.empty()).cropped(to: extent)

        return fringed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: maskImage,
        ])
    }

    // MARK: - Grain

    private func applyGrain(to image: CIImage, params: GrainParams, seed: UInt64,
                            longEdge: CGFloat, quality: Quality) -> CIImage {
        let extent = image.extent
        let grainPixels = max(permilToPixels(params.size, longEdge: longEdge, quality: quality), 1)

        if let kernel = grainKernel {
            let args: [Any] = [
                Float(seed % 65_536), // compact float seed; full seed range not needed for decorrelation
                Float(params.intensity),
                Float(grainPixels),
                Float(params.chromaMix),
                Float(params.shadowWeight),
            ]
            if let out = kernel.apply(extent: extent, arguments: [image] + args) {
                return out
            }
        }
        return grainFallback(image: image, params: params, seed: seed,
                             grainPixels: grainPixels, quality: quality)
    }

    /// Pure Core Image grain: CIRandomGenerator (procedural white noise),
    /// jittered by seed, scaled to grain size, partially desaturated, then
    /// overlay-composited with a luminance-weighted mask.
    ///
    /// Scaling uses nearest-neighbor + a fractional clump blur. Never Lanczos:
    /// smooth-resampling noise turns every grain into a soft circular blob.
    private func grainFallback(image: CIImage, params: GrainParams, seed: UInt64,
                               grainPixels: CGFloat, quality: Quality) -> CIImage {
        let extent = image.extent
        var rng = SeededRandom(seed: seed ^ 0x6772_6169) // decorrelate from other draws
        let jitter = CGAffineTransform(translationX: CGFloat(rng.uniform(0...4096)),
                                       y: CGFloat(rng.uniform(0...4096)))

        var noise = CIImage(color: .gray).cropped(to: extent)
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            noise = random
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: grainPixels, y: grainPixels)
                    .concatenating(jitter))
                .cropped(to: extent)
            // Soften clump edges just enough to kill pixel squares without
            // rounding the grain into dots.
            if grainPixels > 1.2, quality == .full {
                noise = noise.clampedToExtent()
                    .applyingFilter("CIGaussianBlur",
                                    parameters: [kCIInputRadiusKey: grainPixels * 0.25])
                    .cropped(to: extent)
            }
        }

        // Pull toward luma-only grain per chromaMix, then center on 0.5 for
        // overlay blending at the requested intensity.
        noise = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: params.chromaMix,
        ])
        let k = CGFloat(params.intensity)
        noise = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            "inputBiasVector": CIVector(x: 0.5 * (1 - k), y: 0.5 * (1 - k), z: 0.5 * (1 - k), w: 0),
        ])
        let grained = noise.applyingFilter("CIOverlayBlendMode", parameters: [
            kCIInputBackgroundImageKey: image,
        ])

        guard quality == .full, params.shadowWeight > 0.05 else { return grained }

        // Weight grain into shadows/mids: white mask where luma is low.
        let mask = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -CGFloat(params.shadowWeight), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: -CGFloat(params.shadowWeight), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: -CGFloat(params.shadowWeight), w: 0),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
            ])
        return grained.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask,
        ])
    }

    // MARK: - Artifacts

    private func applyFlashFalloff(to image: CIImage, strength: Double,
                                   extent: CGRect, rng: inout SeededRandom) -> CIImage {
        // Flash center wanders slightly shot to shot, like a hand-held point-and-shoot.
        let cx = extent.midX + CGFloat(rng.uniform(-0.06...0.06)) * extent.width
        let cy = extent.midY + CGFloat(rng.uniform(-0.04...0.10)) * extent.height
        let radius = max(extent.width, extent.height)

        let falloff = CIFilter.radialGradient()
        falloff.center = CGPoint(x: cx, y: cy)
        falloff.radius0 = Float(radius * 0.28)
        falloff.radius1 = Float(radius * 0.85)
        let lift = CGFloat(1 + 0.10 * strength)
        falloff.color0 = CIColor(red: lift, green: lift, blue: lift)
        let floor = CGFloat(1 - 0.55 * strength)
        falloff.color1 = CIColor(red: floor, green: floor, blue: floor)
        let gradient = (falloff.outputImage ?? CIImage.empty()).cropped(to: extent)

        return gradient.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
    }

    private func applyLightLeak(to image: CIImage, strength: Double,
                                extent: CGRect, rng: inout SeededRandom) -> CIImage {
        // Leaks enter from a film-gate edge: pick a side, a warm color, a width.
        let side = Int(rng.next() % 4)
        let warm = [
            CIColor(red: 1.0, green: 0.42, blue: 0.12), // orange
            CIColor(red: 1.0, green: 0.20, blue: 0.25), // red-magenta
            CIColor(red: 1.0, green: 0.65, blue: 0.30), // amber
        ][Int(rng.next() % 3)]
        let breadth = CGFloat(rng.uniform(0.18...0.45))

        let g = CIFilter.linearGradient()
        switch side {
        case 0: // left
            g.point0 = CGPoint(x: extent.minX, y: extent.midY)
            g.point1 = CGPoint(x: extent.minX + extent.width * breadth, y: extent.midY)
        case 1: // right
            g.point0 = CGPoint(x: extent.maxX, y: extent.midY)
            g.point1 = CGPoint(x: extent.maxX - extent.width * breadth, y: extent.midY)
        case 2: // top
            g.point0 = CGPoint(x: extent.midX, y: extent.maxY)
            g.point1 = CGPoint(x: extent.midX, y: extent.maxY - extent.height * breadth)
        default: // bottom
            g.point0 = CGPoint(x: extent.midX, y: extent.minY)
            g.point1 = CGPoint(x: extent.midX, y: extent.minY + extent.height * breadth)
        }
        let alpha = CGFloat(strength * rng.uniform(0.5...1.0))
        g.color0 = CIColor(red: warm.red, green: warm.green, blue: warm.blue, alpha: alpha)
        g.color1 = CIColor(red: warm.red, green: warm.green, blue: warm.blue, alpha: 0)
        let leak = (g.outputImage ?? CIImage.empty()).cropped(to: extent)

        return leak.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
    }

    // MARK: - Helpers

    /// Converts a size in ‰ of the long edge into pixels, halved for previews
    /// (previews run at reduced resolution).
    private func permilToPixels(_ permil: Double, longEdge: CGFloat, quality: Quality) -> CGFloat {
        let px = CGFloat(permil) / 1000 * longEdge
        return quality == .preview ? max(px * 0.6, 0.5) : max(px, 0.5)
    }
}

// MARK: - CIImage / UIImage conveniences

extension CIImage {
    func osResampled(scale: CGFloat) -> CIImage {
        applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])
    }

    func osScaledAlpha(_ alpha: CGFloat) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
        ])
    }

    /// Isolates channels by zeroing the others (used by the CA pass).
    func osChannel(r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
        ])
    }
}

extension UIImage {
    /// Bakes orientation so the CI pipeline always sees upright pixels.
    func osNormalizedUp() -> UIImage? {
        if imageOrientation == .up, cgImage != nil { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
