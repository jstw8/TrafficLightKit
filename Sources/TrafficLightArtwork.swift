import AppKit
import SwiftUI

/// Runtime artwork for the standard red, yellow, and green traffic lights.
/// Actions and accessibility belong to the enclosing semantic control.
@MainActor
struct TrafficLightArtwork: NSViewRepresentable {
    let colorName: String
    let isKey: Bool
    let isEnabled: Bool
    let isPressed: Bool
    let isColorActive: Bool
    let customTint: Color?

    init(colorName: String, isKey: Bool, isEnabled: Bool = true, isPressed: Bool = false,
         isColorActive: Bool = false, customTint: Color? = nil) {
        self.colorName = colorName
        self.isKey = isKey
        self.isEnabled = isEnabled
        self.isPressed = isPressed
        self.isColorActive = isColorActive
        self.customTint = customTint
    }

    func makeNSView(context: Context) -> Container {
        Container(buttonType: buttonType)
    }

    func updateNSView(_ view: Container, context: Context) {
        view.configure(buttonType: buttonType, colorName: colorName, isKey: isKey, isEnabled: isEnabled,
                       isPressed: isPressed, isColorActive: isColorActive,
                       isDark: context.environment.colorScheme == .dark, customTint: customTint)
    }

    private var buttonType: NSWindow.ButtonType {
        switch colorName.lowercased() {
        case "yellow": .miniaturizeButton
        case "green": .zoomButton
        default: .closeButton
        }
    }

    @MainActor
    final class Container: NSView {
        private let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        private var currentType: NSWindow.ButtonType
        private var button: NSButton?
        private var fallback: TrafficLightMeasuredMaterialView?

        init(buttonType: NSWindow.ButtonType) {
            currentType = buttonType
            super.init(frame: .zero)
            replaceButton(with: buttonType)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard let button else { return }
            button.frame = NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
            fallback?.frame = NSRect(x: (bounds.width - 18) / 2, y: (bounds.height - 18) / 2, width: 18, height: 18)
        }

        func configure(buttonType: NSWindow.ButtonType, colorName: String, isKey: Bool, isEnabled: Bool,
                       isPressed: Bool, isColorActive: Bool, isDark: Bool, customTint: Color?) {
            if currentType != buttonType { replaceButton(with: buttonType) }
            guard let button else { return }
            let usesFallback = isEnabled && ((!isKey && isColorActive && !isPressed)
                || (customTint != nil && (isKey || isColorActive || isPressed)))
            button.isEnabled = isEnabled
            button.highlight(isPressed)
            button.isHidden = usesFallback
            if usesFallback {
                if fallback == nil {
                    let material = TrafficLightMeasuredMaterialView(frame: .zero)
                    fallback = material
                    addSubview(material)
                    needsLayout = true
                }
                // Pressed native controls retain radiance beyond the SDR fitted
                // patch. The measured rest material plus exposure keeps that response.
                fallback?.configure(colorName: colorName, dark: isDark, customTint: customTint)
            }
            fallback?.isHidden = !usesFallback
            if isPressed, usesFallback, let exposure = CIFilter(name: "CIExposureAdjust") {
                exposure.setValue(1, forKey: kCIInputEVKey)
                fallback?.contentFilters = [exposure]
            } else {
                fallback?.contentFilters = []
            }
        }

        private func replaceButton(with type: NSWindow.ButtonType) {
            button?.removeFromSuperview()
            currentType = type
            guard let button = NSWindow.standardWindowButton(type, for: style) else {
                self.button = nil
                return
            }
            button.target = nil
            button.action = nil
            button.keyEquivalent = ""
            button.setAccessibilityHidden(true)
            self.button = button
            addSubview(button)
            needsLayout = true
        }
    }
}
