import AppKit
import CoreGraphics
import SwiftUI

/// Rasterizes macOS 27-calibrated RGB resting traffic-light material locally.
/// Coefficients were extracted from Shelfie calibration source `48b7ecb`; no
/// captured pixels are read or shipped at runtime.
@MainActor
final class TrafficLightMeasuredMaterialView: NSView {
    private struct Tint: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private struct Configuration: Equatable {
        let color: String
        let dark: Bool
        let tint: Tint?
        let scale: Double
    }

    private final class ImageBox: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let imageCache: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 64
        return cache
    }()

    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshForBackingScaleChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshForBackingScaleChange()
    }

    func configure(colorName: String, dark: Bool, customTint: Color?) {
        let color = Self.canonicalColor(colorName)
        let tint = Self.tint(from: customTint)
        let next = Configuration(color: color, dark: dark, tint: tint, scale: backingScale)
        guard next != configuration else { return }
        configuration = next
        installImage(for: next)
    }

    private var backingScale: Double {
        let scale = window?.backingScaleFactor ?? 2
        return scale.isFinite && scale > 0 ? Double(scale) : 2
    }

    private func refreshForBackingScaleChange() {
        guard let old = configuration else { return }
        let next = Configuration(color: old.color, dark: old.dark, tint: old.tint,
                                 scale: backingScale)
        guard next != old else { return }
        configuration = next
        installImage(for: next)
    }

    private func installImage(for configuration: Configuration) {
        let key = Self.cacheKey(configuration)
        let image: CGImage
        if let cached = Self.imageCache.object(forKey: key as NSString) {
            image = cached.image
        } else {
            guard let generated = Self.makeImage(configuration: configuration) else {
                layer?.contents = nil
                return
            }
            Self.imageCache.setObject(ImageBox(generated), forKey: key as NSString)
            image = generated
        }
        layer?.contentsScale = CGFloat(configuration.scale)
        layer?.contents = image
    }

    private static func canonicalColor(_ value: String) -> String {
        switch value.lowercased() {
        case "yellow", "green", "red": return value.lowercased()
        default: return "red"
        }
    }

    private static func tint(from color: Color?) -> Tint? {
        guard let color, let sRGB = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return Tint(red: Double(sRGB.redComponent), green: Double(sRGB.greenComponent),
                    blue: Double(sRGB.blueComponent), alpha: Double(sRGB.alphaComponent))
    }

    private static func cacheKey(_ configuration: Configuration) -> String {
        func part(_ value: Double) -> String { String(format: "%.8f", value) }
        let tint = configuration.tint.map { "\(part($0.red)),\(part($0.green)),\(part($0.blue)),\(part($0.alpha))" } ?? "none"
        return "\(configuration.color)|\(configuration.dark)|\(part(configuration.scale))|\(tint)"
    }

    private static func makeImage(configuration: Configuration) -> CGImage? {
        let family = configuration.dark ? "Dark" : "Light"
        let key = "\(family)-\(configuration.color)-rest"
        let fallbackKey = "\(family)-red-rest"
        guard let rows = TrafficLightMeasuredPresets.profiles[key] ?? TrafficLightMeasuredPresets.profiles[fallbackKey],
              rows.count == TrafficLightMeasuredPresets.coreTerms + TrafficLightMeasuredPresets.knots.count * TrafficLightMeasuredPresets.modes,
              rows.allSatisfy({ $0.count == 4 }) else { return nil }
        let width = Int((18 * configuration.scale).rounded())
        let height = width
        guard width > 0 else { return nil }
        let centerReference = sampledColor(rows: rows, x: 0, y: 0)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixelY in 0..<height {
            for pixelX in 0..<width {
                var sum = SIMD4<Double>(repeating: 0)
                for sampleY in 0..<4 {
                    for sampleX in 0..<4 {
                        let x = (Double(pixelX) + (Double(sampleX) + 0.5) / 4) / configuration.scale - 9
                        let y = (Double(pixelY) + (Double(sampleY) + 0.5) / 4) / configuration.scale - 9
                        sum += sampledColor(rows: rows, x: x, y: y)
                    }
                }
                var color = sum / 16
                color.w = min(max(color.w, 0), 1)
                color.x = min(max(color.x, 0), color.w)
                color.y = min(max(color.y, 0), color.w)
                color.z = min(max(color.z, 0), color.w)
                if let tint = configuration.tint {
                    color = applying(tint: tint, to: color, reference: centerReference)
                }
                let offset = (pixelY * width + pixelX) * 4
                bytes[offset] = UInt8((color.x * 255).rounded())
                bytes[offset + 1] = UInt8((color.y * 255).rounded())
                bytes[offset + 2] = UInt8((color.z * 255).rounded())
                bytes[offset + 3] = UInt8((color.w * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                                | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func sampledColor(rows: [[Double]], x: Double, y: Double) -> SIMD4<Double> {
        let radius = hypot(x, y)
        let theta = radius > 0 ? acos(min(max(y / radius, -1), 1)) : 0
        var result = SIMD4<Double>(repeating: 0)
        let coreWeight = min(max((5.5 - radius) / 0.5, 0), 1)
        for term in 0..<TrafficLightMeasuredPresets.coreTerms {
            let row = rows[term]
            result += SIMD4(row[0], row[1], row[2], row[3]) * (coreWeight * pow(y / 7, Double(term)))
        }
        for knotIndex in TrafficLightMeasuredPresets.knots.indices {
            let radial = radialBasis(radius, index: knotIndex)
            guard radial != 0 else { continue }
            for mode in 0..<TrafficLightMeasuredPresets.modes {
                let coefficient = radial * cos(Double(mode) * theta)
                let row = rows[TrafficLightMeasuredPresets.coreTerms + knotIndex * TrafficLightMeasuredPresets.modes + mode]
                result += SIMD4(row[0], row[1], row[2], row[3]) * coefficient
            }
        }
        return result
    }

    private static func radialBasis(_ radius: Double, index: Int) -> Double {
        let knots = TrafficLightMeasuredPresets.knots
        let left = index == 0 ? 5 : knots[index - 1]
        let right = index == knots.count - 1 ? 10 : knots[index + 1]
        return min(max(min((radius - left) / (knots[index] - left),
                           (right - radius) / (right - knots[index])), 0), 1)
    }

    /// Custom colors are inferred from the fitted center color: unpremultiply,
    /// shift hue and scale saturation/value in HSV, then restore the original
    /// alpha. Per-pixel value relative to the center is retained, preserving
    /// fitted highlight contrast; this is an inference for non-native colors.
    private static func applying(tint: Tint, to color: SIMD4<Double>, reference: SIMD4<Double>) -> SIMD4<Double> {
        guard color.w > 0, reference.w > 0 else { return color }
        let source = hsv(red: color.x / color.w, green: color.y / color.w, blue: color.z / color.w)
        let base = hsv(red: reference.x / reference.w, green: reference.y / reference.w, blue: reference.z / reference.w)
        let target = hsv(red: tint.red, green: tint.green, blue: tint.blue)
        let saturationScale = base.saturation > 0 ? target.saturation / base.saturation : 1
        let valueScale = base.value > 0 ? target.value / base.value : 1
        let transformed = rgb(hue: source.hue + target.hue - base.hue,
                              saturation: min(max(source.saturation * saturationScale, 0), 1),
                              value: min(max(source.value * valueScale, 0), 1))
        // `customTint` supplies color only. Retaining fitted coverage alpha
        // keeps the rim and highlight falloff instead of flattening it.
        let alpha = color.w
        return SIMD4(transformed.red * alpha, transformed.green * alpha, transformed.blue * alpha, alpha)
    }

    private static func hsv(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue), delta = maximum - minimum
        let hue: Double
        if delta == 0 { hue = 0 }
        else if maximum == red { hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == green { hue = 60 * ((blue - red) / delta + 2) }
        else { hue = 60 * ((red - green) / delta + 4) }
        return (hue < 0 ? hue + 360 : hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    private static func rgb(hue: Double, saturation: Double, value: Double) -> (red: Double, green: Double, blue: Double) {
        let normalized = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let chroma = value * saturation, segment = normalized / 60, second = chroma * (1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1))
        let pair: (Double, Double, Double)
        switch Int(segment) {
        case 0: pair = (chroma, second, 0)
        case 1: pair = (second, chroma, 0)
        case 2: pair = (0, chroma, second)
        case 3: pair = (0, second, chroma)
        case 4: pair = (second, 0, chroma)
        default: pair = (chroma, 0, second)
        }
        let match = value - chroma
        return (pair.0 + match, pair.1 + match, pair.2 + match)
    }
}
