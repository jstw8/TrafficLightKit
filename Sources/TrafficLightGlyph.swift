import AppKit
import SwiftUI

@MainActor
struct TrafficLightGlyph: View {
    let symbolName: String
    let colorName: String
    let isColorActive: Bool
    var customTint: Color?
    var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private var preset: (scale: CGFloat, stroke: CGFloat, ink: Double) {
        switch symbolName {
        case "xmark": (0.99375, 0.9921875, 0.99375)
        case "minus": (0.9984375, 1, 1)
        case "plus": (0.9984375, 0.998388671875, 1)
        case "native-fullscreen": (0.9859375, 1, 0.9953125)
        default: (1, 1, 1)
        }
    }

    private var ink: Color {
        guard isColorActive else { return .primary.opacity(0.6) }
        if customTint != nil { return customInk }
        let rgb: (Double, Double, Double)
        switch (colorScheme, colorName.lowercased()) {
        case (.dark, "red"): rgb = (140, 0, 0)
        case (.dark, "yellow"): rgb = (166, 58, 1)
        case (.dark, "green"): rgb = (46, 115, 1)
        case (_, "red"): rgb = (163, 1, 0)
        case (_, "yellow"): rgb = (193, 68, 1)
        case (_, "green"): rgb = (54, 136, 1)
        default: rgb = (0, 0, 0)
        }
        return Color(.sRGB, red: min(rgb.0 / 255 * preset.ink, 1),
                     green: min(rgb.1 / 255 * preset.ink, 1), blue: min(rgb.2 / 255 * preset.ink, 1))
    }

    private var customInk: Color {
        guard let customTint, let color = NSColor(customTint).usingColorSpace(.sRGB) else {
            let pressedGain = symbolName == "native-document-edited" ? 1 : (isPressed ? 1.33 : 1)
            return Color(hue: 0.58, saturation: 1,
                         brightness: min((colorScheme == .dark ? 0.3436 : 0.4) * pressedGain * preset.ink, 1))
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let pressedGain = symbolName == "native-document-edited" ? 1 : (isPressed ? 1.33 : 1)
        let gain = (colorScheme == .dark ? 0.58 : 0.65) * pressedGain * preset.ink
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: min(Double(brightness) * gain, 1))
    }

    var body: some View {
        Group {
            switch symbolName {
            case "native-document-edited": Circle().fill(ink).frame(width: 5 * preset.scale, height: 5 * preset.scale)
            case "xmark": stroked(xmarkPath)
            case "minus": stroked(minusPath)
            case "plus": stroked(plusPath)
            case "native-fullscreen": fullscreenGlyph
            default: EmptyView()
            }
        }
        .frame(width: 14, height: 14)
    }

    private func stroked(_ path: Path) -> some View {
        path.stroke(ink, style: StrokeStyle(lineWidth: 2 * preset.stroke, lineCap: .round))
    }

    private var xmarkPath: Path {
        var path = Path()
        path.move(to: point(-2.625, -2.625))
        path.addLine(to: point(2.625, 2.625))
        path.move(to: point(2.625, -2.625))
        path.addLine(to: point(-2.625, 2.625))
        return path
    }

    private var minusPath: Path {
        var path = Path()
        path.move(to: point(-3, 0))
        path.addLine(to: point(3, 0))
        return path
    }

    private var plusPath: Path {
        var path = minusPath
        path.move(to: point(0, -3))
        path.addLine(to: point(0, 3))
        return path
    }

    private var fullscreenGlyph: some View {
        ZStack {
            roundedTriangle(point(-3, -3), point(1.9921875, -3), point(-3, 1.9921875)).fill(ink)
            roundedTriangle(point(3, 3), point(-1.9921875, 3), point(3, -1.9921875)).fill(ink)
        }
    }

    private func roundedTriangle(_ first: CGPoint, _ second: CGPoint, _ third: CGPoint) -> Path {
        var path = Path()
        let radius: CGFloat = 0.2671875 * preset.scale
        path.move(to: first)
        path.addArc(tangent1End: second, tangent2End: third, radius: radius)
        path.addArc(tangent1End: third, tangent2End: first, radius: radius)
        path.addArc(tangent1End: first, tangent2End: second, radius: radius)
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 7 + x * preset.scale, y: 7 + y * preset.scale)
    }
}
