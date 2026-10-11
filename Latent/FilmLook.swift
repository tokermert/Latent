import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Latent's own film looks. Applied only to the saved "developed" photo (and the picker samples);
/// the live preview and the original file stay untouched.
enum FilmLook {
    /// Every value that shapes a look lives here, so the looks can be tuned in one place.
    /// Use `FilmLookPreviewGrid` (Xcode Previews) to see all films on all samples while tuning.
    struct Parameters {
        /// Per-channel mix in the working (linear) space. Rows produce R, G, B from (r, g, b).
        /// Use it for white balance (gains on the diagonal) or a black-and-white channel mix.
        struct Mix {
            var r: SIMD3<Float>, g: SIMD3<Float>, b: SIMD3<Float>
            static func gains(r: Float, g: Float, b: Float) -> Mix {
                Mix(r: [r, 0, 0], g: [0, g, 0], b: [0, 0, b])
            }
            /// Grey from weighted channels; more red and less blue darkens skies like a red filter.
            static func mono(_ weights: SIMD3<Float>) -> Mix { Mix(r: weights, g: weights, b: weights) }
        }
        /// nil skips the step.
        var mix: Mix?
        /// `CIColorControls`; 1 / 1 / 0 is neutral.
        var saturation: Float = 1
        var contrast: Float = 1
        var brightness: Float = 0
        /// Five `CIToneCurve` points (x: in, y: out). nil skips the step. Lift point 0's y for
        /// faded blacks, lower point 1's y for deeper shadows, lower point 4's y for softer highlights.
        var toneCurve: [CGPoint]?
        /// `CIVignetteEffect` intensity; 0 is off. Keep it subtle (≤ 0.3).
        var vignette: Float = 0
        /// Grain strength: ± change of each pixel's light at full-size midtones. 0 is off.
        var grain: Float = 0
        /// Grain particle size as a fraction of the long edge, so the grain looks the same
        /// on a 12 MP photo and on a small preview.
        var grainSize: Float = 1.0 / 2600
        /// Grain left in deep shadows and bright highlights, relative to midtones (0...1).
        var grainEdgeFloor: Float = 0.3
    }

    static func parameters(for stock: FilmStock) -> Parameters {
        switch stock.id {
        case FilmStock.gold200.id:
            // Warm and golden, soft contrast, raised blacks, gentle highlights, fine grain.
            return Parameters(
                mix: .gains(r: 1.05, g: 1.0, b: 0.87),
                saturation: 1.03, contrast: 0.95, brightness: 0,
                toneCurve: [CGPoint(x: 0, y: 0.05), CGPoint(x: 0.25, y: 0.28), CGPoint(x: 0.5, y: 0.53),
                            CGPoint(x: 0.75, y: 0.78), CGPoint(x: 1, y: 0.97)],
                vignette: 0.18, grain: 0.022, grainSize: 1.0 / 2800)
        case FilmStock.slide100.id:
            // Slide: rich colour, deep shadows, slightly cool and clean, almost no grain.
            return Parameters(
                mix: .gains(r: 0.98, g: 1.0, b: 1.04),
                saturation: 1.25, contrast: 1.08, brightness: -0.01,
                toneCurve: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.19), CGPoint(x: 0.5, y: 0.5),
                            CGPoint(x: 0.75, y: 0.8), CGPoint(x: 1, y: 1)],
                vignette: 0.12, grain: 0.008, grainSize: 1.0 / 3200)
        case FilmStock.mono400.id:
            // Black and white through a red-filter style mix, strong contrast, visible grain.
            return Parameters(
                mix: .mono([0.55, 0.38, 0.07]),
                saturation: 1, contrast: 1.08, brightness: 0,
                toneCurve: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.17), CGPoint(x: 0.5, y: 0.5),
                            CGPoint(x: 0.75, y: 0.83), CGPoint(x: 1, y: 1)],
                vignette: 0, grain: 0.05, grainSize: 1.0 / 2200, grainEdgeFloor: 0.4)
        default:
            // COLOR 400: the original Latent look, unchanged (same filter, same values), plus a
            // barely visible grain. Set `grain` to 0 for output identical to earlier versions.
            return Parameters(saturation: 0.9, contrast: 1.04, brightness: 0.01, grain: 0.012)
        }
    }

    /// `seed` picks where the grain pattern starts; the same seed always gives the same grain.
    static func apply(_ image: CIImage, stock: FilmStock, seed: UInt64) -> CIImage {
        apply(image, parameters: parameters(for: stock), seed: seed)
    }

    static func apply(_ image: CIImage, parameters p: Parameters, seed: UInt64) -> CIImage {
        let extent = image.extent
        var output = image

        if let mix = p.mix {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = output
            matrix.rVector = vector(mix.r); matrix.gVector = vector(mix.g); matrix.bVector = vector(mix.b)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            output = matrix.outputImage ?? output
        }

        let color = CIFilter.colorControls()
        color.inputImage = output
        color.saturation = p.saturation; color.contrast = p.contrast; color.brightness = p.brightness
        output = color.outputImage ?? output

        if let points = p.toneCurve, points.count == 5 {
            let curve = CIFilter.toneCurve()
            curve.inputImage = output
            curve.point0 = points[0]; curve.point1 = points[1]; curve.point2 = points[2]
            curve.point3 = points[3]; curve.point4 = points[4]
            output = curve.outputImage ?? output
        }

        if p.vignette > 0 {
            let vignette = CIFilter.vignetteEffect()
            vignette.inputImage = output
            vignette.center = CGPoint(x: extent.midX, y: extent.midY)
            vignette.radius = Float(hypot(extent.width, extent.height) / 2 * 0.8)
            vignette.intensity = p.vignette
            vignette.falloff = 0.6
            output = vignette.outputImage?.cropped(to: extent) ?? output
        }

        if p.grain > 0, let grained = grain(on: output, parameters: p, seed: seed) {
            output = grained
        }
        return output.cropped(to: extent)
    }

    /// Monochrome grain, multiplied into the image: strongest in midtones, scaled to image size.
    private static func grain(on image: CIImage, parameters p: Parameters, seed: UInt64) -> CIImage? {
        let extent = image.extent
        let longEdge = Float(max(extent.width, extent.height))
        guard longEdge > 0, let random = CIFilter.randomGenerator().outputImage else { return nil }
        // Particles smaller than a pixel average out, as when a full-size photo is scaled down.
        let particle = longEdge * p.grainSize
        let cell = max(1, particle)
        let amount = p.grain * min(1, particle)

        // CIRandomGenerator is a fixed pattern; the seed moves to a different part of it.
        let offset = CGPoint(x: CGFloat(seed % 4096), y: CGFloat((seed >> 12) % 4096))
        var noise = random
            .transformed(by: CGAffineTransform(translationX: -offset.x, y: -offset.y))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(cell), y: CGFloat(cell)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        if cell > 1 {
            let soften = CIFilter.gaussianBlur()
            soften.inputImage = noise; soften.radius = cell * 0.35
            noise = soften.outputImage ?? noise
        }
        // One random channel → grey modulation around 1: [1 - amount, 1 + amount].
        let toModulation = CIFilter.colorMatrix()
        toModulation.inputImage = noise
        let spread = CIVector(x: CGFloat(2 * amount), y: 0, z: 0, w: 0)
        toModulation.rVector = spread; toModulation.gVector = spread; toModulation.bVector = spread
        toModulation.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let base = CGFloat(1 - amount)
        toModulation.biasVector = CIVector(x: base, y: base, z: base, w: 1)
        guard let modulation = toModulation.outputImage?.cropped(to: extent),
              let mask = midtoneMask(for: image, floor: p.grainEdgeFloor) else { return nil }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = modulation
        blend.backgroundImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        blend.maskImage = mask
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = blend.outputImage
        multiply.backgroundImage = image
        return multiply.outputImage?.cropped(to: extent)
    }

    /// Grey mask: 1 in midtones, `floor` at pure black and white (floor + (1 - floor) · 4L(1 - L)).
    private static func midtoneMask(for image: CIImage, floor: Float) -> CIImage? {
        let luma = CIFilter.colorMatrix()
        luma.inputImage = image
        let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        luma.rVector = weights; luma.gVector = weights; luma.bVector = weights
        luma.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        luma.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        // Perceptual lightness, so "midtones" means what the eye sees as midtones.
        let perceptual = CIFilter.linearToSRGBToneCurve()
        perceptual.inputImage = luma.outputImage
        guard let lightness = perceptual.outputImage else { return nil }

        let invert = CIFilter.colorMatrix()
        invert.inputImage = lightness
        invert.rVector = CIVector(x: -1, y: 0, z: 0, w: 0)
        invert.gVector = CIVector(x: 0, y: -1, z: 0, w: 0)
        invert.bVector = CIVector(x: 0, y: 0, z: -1, w: 0)
        invert.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        invert.biasVector = CIVector(x: 1, y: 1, z: 1, w: 1)

        let product = CIFilter.multiplyCompositing()
        product.inputImage = invert.outputImage
        product.backgroundImage = lightness

        let scale = CIFilter.colorMatrix()
        scale.inputImage = product.outputImage
        let gain = CGFloat(4 * (1 - floor))
        scale.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        scale.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        scale.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let lift = CGFloat(floor)
        scale.biasVector = CIVector(x: lift, y: lift, z: lift, w: 1)

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = scale.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage?.cropped(to: image.extent)
    }

    private static func vector(_ v: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: 0)
    }

    /// Stable grain seed for a capture.
    static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.enumerated().reduce(UInt64(0)) { $0 ^ (UInt64($1.element) << UInt64(($1.offset % 8) * 8)) }
        }
    }
}
