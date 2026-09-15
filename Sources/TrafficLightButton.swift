import AppKit
import SwiftUI

@MainActor
enum WindowTrafficLightMetrics {
    static let height: CGFloat = 28

    static let spacing: CGFloat = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 100),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        guard let close = window.standardWindowButton(.closeButton),
              let minimize = window.standardWindowButton(.miniaturizeButton)
        else { return 20 }
        return minimize.frame.midX - close.frame.midX
    }()

    static let diameter: CGFloat = {
        NSWindow.standardWindowButton(.closeButton, for: [.titled])?.intrinsicContentSize.width ?? 12
    }()
}

private struct TrafficLightGroupHoverKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var trafficLightGroupHovered: Bool {
        get { self[TrafficLightGroupHoverKey.self] }
        set { self[TrafficLightGroupHoverKey.self] = newValue }
    }
}

@MainActor
/// A horizontally compact traffic-light group whose glyphs reveal together on hover.
public struct TrafficLightGroup<Content: View>: View {
    private let content: Content
    @State private var isHovered = false

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) { content }
            .fixedSize()
            .environment(\.trafficLightGroupHovered, isHovered)
            .controlSize(.regular)
            .background(TrafficLightGroupHoverReader { isHovered = $0 })
    }
}

@MainActor
/// A macOS 27-styled traffic-light control with caller-owned action semantics.
public struct TrafficLightButton: View {
    /// The supported standard traffic-light appearances.
    public enum Kind: Sendable {
        case close
        case minimize
        case zoom
    }

    private let kind: Kind
    private let tint: Color?
    private let label: String
    private let isDocumentEdited: Bool
    private let action: () -> Void

    @Environment(\.trafficLightGroupHovered) private var groupHovered
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var optionHeld = false
    @FocusState private var isFocused: Bool
    @StateObject private var windowState = WindowState()

    /// Creates a control whose action is supplied by the embedding application.
    public init(
        _ kind: Kind,
        tint: Color? = nil,
        label: String? = nil,
        isDocumentEdited: Bool = false,
        action: @escaping () -> Void
    ) {
        self.kind = kind
        self.tint = tint
        self.label = label ?? Self.defaultLabel(for: kind)
        self.isDocumentEdited = isDocumentEdited
        self.action = action
    }

    private static func defaultLabel(for kind: Kind) -> String {
        switch kind {
        case .close: "Close"
        case .minimize: "Minimize"
        case .zoom: "Zoom"
        }
    }

    private var colorName: String {
        switch kind {
        case .close: "red"
        case .minimize: "yellow"
        case .zoom: "green"
        }
    }

    private var glyphVisible: Bool {
        groupHovered || isHovered || isFocused || (kind == .close && isDocumentEdited)
    }

    private var isColorActive: Bool {
        windowState.isKey || groupHovered || isHovered || isFocused
    }

    private var symbolName: String {
        switch kind {
        case .close:
            return isDocumentEdited && !groupHovered && !isHovered && !isFocused && !isPressed
                ? "native-document-edited" : "xmark"
        case .minimize:
            return "minus"
        case .zoom:
            return optionHeld && glyphVisible ? "plus" : "native-fullscreen"
        }
    }

    public var body: some View {
        ZStack {
            TrafficLightArtwork(
                colorName: colorName,
                isKey: windowState.isKey,
                isEnabled: isEnabled,
                isPressed: isPressed,
                isColorActive: isColorActive,
                customTint: tint
            )
            .frame(width: WindowTrafficLightMetrics.diameter, height: WindowTrafficLightMetrics.diameter)
            TrafficLightGlyph(
                symbolName: symbolName,
                colorName: colorName,
                isColorActive: isColorActive,
                customTint: tint,
                isPressed: isPressed
            )
            .opacity(isEnabled && glyphVisible && !(isPressed && tint == nil) ? 1 : 0)
            .allowsHitTesting(false)
            TrafficLightActionButton(
                label: label,
                isEnabled: isEnabled,
                action: action,
                onPressedChanged: { isPressed = $0 }
            )
            .frame(width: WindowTrafficLightMetrics.spacing, height: WindowTrafficLightMetrics.height)
        }
        .frame(width: WindowTrafficLightMetrics.spacing, height: WindowTrafficLightMetrics.height)
        .focusable()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .background(WindowStateReader(state: windowState))
        .background {
            if kind == .zoom {
                TrafficLightOptionModifierReader(isObserving: glyphVisible && isEnabled) {
                    optionHeld = $0
                }
            }
        }
    }
}

struct TrafficLightActionButton: NSViewRepresentable {
    let label: String
    let isEnabled: Bool
    let action: () -> Void
    var onPressedChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator,
                              action: #selector(Coordinator.performAction))
        let cell = HighlightReportingButtonCell()
        cell.title = ""
        cell.onPressedChanged = onPressedChanged
        button.cell = cell
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.isBordered = false
        button.isEnabled = isEnabled
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(label)
        button.toolTip = label
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        (button.cell as? HighlightReportingButtonCell)?.onPressedChanged = onPressedChanged
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private final class HighlightReportingButtonCell: NSButtonCell {
    var onPressedChanged: (Bool) -> Void = { _ in }

    override var isHighlighted: Bool {
        didSet { onPressedChanged(isHighlighted) }
    }
}

private struct TrafficLightOptionModifierReader: NSViewRepresentable {
    let isObserving: Bool
    let onOptionChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrafficLightOptionModifierTrackingView {
        let view = TrafficLightOptionModifierTrackingView()
        view.onOptionChanged = onOptionChanged
        view.setObserving(isObserving)
        return view
    }

    func updateNSView(_ view: TrafficLightOptionModifierTrackingView, context: Context) {
        view.onOptionChanged = onOptionChanged
        view.setObserving(isObserving)
    }

    static func dismantleNSView(_ view: TrafficLightOptionModifierTrackingView, coordinator: ()) {
        view.dismantle()
    }
}

@MainActor
private final class TrafficLightOptionModifierTrackingView: NSView {
    var onOptionChanged: ((Bool) -> Void)?
    private var localMonitor: Any?
    private var pollingTimer: Timer?
    private var isObserving = false
    private var lastPublished: Bool?
    private var publicationGeneration = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            invalidateMonitor()
        } else if isObserving {
            installMonitorIfNeeded()
            startPollingIfNeeded()
            scheduleCurrentModifierFlags()
        }
    }

    func setObserving(_ isObserving: Bool) {
        self.isObserving = isObserving
        guard isObserving, window != nil else {
            invalidateMonitor()
            return
        }
        installMonitorIfNeeded()
        startPollingIfNeeded()
        scheduleCurrentModifierFlags()
    }

    func dismantle() {
        isObserving = false
        invalidateMonitor()
    }

    private func scheduleCurrentModifierFlags() {
        let generation = publicationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publicationGeneration == generation,
                  self.isObserving, self.window != nil
            else { return }
            self.publishIfChanged(NSEvent.modifierFlags.contains(.option))
        }
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.publishIfChanged(event.modifierFlags.contains(.option))
            return event
        }
    }

    private func invalidateMonitor() {
        publicationGeneration &+= 1
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        lastPublished = nil
    }

    private func startPollingIfNeeded() {
        guard pollingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishIfChanged(NSEvent.modifierFlags.contains(.option))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func publishIfChanged(_ isOptionHeld: Bool) {
        guard isObserving, window != nil, lastPublished != isOptionHeld else { return }
        lastPublished = isOptionHeld
        onOptionChanged?(isOptionHeld)
    }

    isolated deinit {
        pollingTimer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

private struct TrafficLightGroupHoverReader: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrafficLightGroupTrackingView {
        let view = TrafficLightGroupTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrafficLightGroupTrackingView, context: Context) {
        view.onHover = onHover
    }

    static func dismantleNSView(_ view: TrafficLightGroupTrackingView, coordinator: ()) {
        view.onHover = nil
    }
}

@MainActor
private final class TrafficLightGroupTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
