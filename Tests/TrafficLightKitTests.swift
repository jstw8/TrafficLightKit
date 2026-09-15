import AppKit
import SwiftUI
import XCTest
@testable import TrafficLightKit

nonisolated final class TrafficLightKitTests: XCTestCase {
    @MainActor private var kinds: [TrafficLightButton.Kind] { [.close, .minimize, .zoom] }

    @MainActor func testReadmeGroupExposesThreeIndependentAccessibleActions() throws {
        var calls = [0, 0, 0]
        let fixture = host(WindowButtons(
            onClose: { calls[0] += 1 },
            onMinimize: { calls[1] += 1 },
            onZoom: { calls[2] += 1 }
        ))
        defer { dispose(fixture.window) }
        let buttons = actionButtons(in: fixture.view)
        XCTAssertEqual(buttons.count, 3)
        for (index, label) in ["Close", "Minimize", "Zoom"].enumerated() {
            let button = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == label })
            XCTAssertEqual(button.accessibilityRole(), .button)
            XCTAssertEqual(button.toolTip, label)
            XCTAssertEqual(button.frame.height, 28, accuracy: 0.01)
            button.performClick(nil)
            XCTAssertEqual(calls[index], 1)
        }
        XCTAssertEqual(calls, [1, 1, 1])
        XCTAssertTrue(fixture.window.isVisible, "The library must not install its own close action")
    }

    @MainActor func testDisabledButtonsNeverInvokeTheirCallbacks() throws {
        for kind in kinds {
            var calls = 0
            let fixture = host(TrafficLightButton(kind) { calls += 1 }.disabled(true))
            defer { dispose(fixture.window) }
            let button = try XCTUnwrap(actionButtons(in: fixture.view).first)
            XCTAssertFalse(button.isEnabled)
            button.performClick(nil)
            XCTAssertEqual(calls, 0)
        }
    }

    @MainActor func testCustomTintAndUpdatedCallbackPreserveButtonSemantics() throws {
        var firstCalls = 0
        var replacementCalls = 0
        let fixture = host(TrafficLightButton(.close, tint: .purple, label: "Dismiss") {
            firstCalls += 1
        })
        defer { dispose(fixture.window) }
        var button = try XCTUnwrap(actionButtons(in: fixture.view).first)
        XCTAssertEqual(button.accessibilityLabel(), "Dismiss")
        button.performClick(nil)
        XCTAssertEqual(firstCalls, 1)

        fixture.view.rootView = AnyView(TrafficLightButton(.close, tint: .orange, label: "Finish") {
            replacementCalls += 1
        })
        settle(fixture.view)
        button = try XCTUnwrap(actionButtons(in: fixture.view).first)
        XCTAssertEqual(button.accessibilityLabel(), "Finish")
        XCTAssertEqual(button.toolTip, "Finish")
        button.performClick(nil)
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(replacementCalls, 1)
    }

    @MainActor func testDragOutsideCancelsAndReentryActivatesOnceForEveryKind() throws {
        for kind in kinds {
            var calls = 0
            let fixture = host(TrafficLightButton(kind) { calls += 1 })
            defer { dispose(fixture.window) }
            let button = try XCTUnwrap(actionButtons(in: fixture.view).first)
            try track(button, in: fixture.window, reenter: false)
            XCTAssertEqual(calls, 0)
            try track(button, in: fixture.window, reenter: true)
            XCTAssertEqual(calls, 1)
            XCTAssertFalse(button.isHighlighted)
        }
    }

    @MainActor func testWindowStateReattachesAndIgnoresPreviousWindowNotifications() {
        let first = StateWindow()
        let second = StateWindow()
        let state = WindowState()
        first.reportsKey = true
        state.attach(to: first)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertTrue(state.isKey)

        second.reportsKey = true
        state.attach(to: second)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        second.reportsKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
        XCTAssertTrue(state.isKey, "Notifications from a former host must not refresh the new host")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: second)
        XCTAssertFalse(state.isKey)
        state.attach(to: nil)
    }

    @MainActor private func host(_ content: some View) -> (window: NSWindow, view: NSHostingView<AnyView>) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: AnyView(content))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        settle(view)
        return (window, view)
    }

    @MainActor private func settle(_ view: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.window?.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
    }

    @MainActor private func dispose(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    @MainActor private func actionButtons(in view: NSView) -> [NSButton] {
        let button = (view as? NSButton).flatMap { $0.action == nil ? nil : $0 }
        return (button.map { [$0] } ?? []) + view.subviews.flatMap { actionButtons(in: $0) }
    }

    @MainActor private func track(_ button: NSButton, in window: NSWindow, reenter: Bool) throws {
        let frame = button.convert(button.bounds, to: nil)
        let inside = NSPoint(x: frame.midX, y: frame.midY)
        let outside = NSPoint(x: frame.maxX + 35, y: frame.midY)
        func event(_ type: NSEvent.EventType, at point: NSPoint, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: number, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        var queued = [try event(.leftMouseDragged, at: outside, number: 2)]
        if reenter { queued.append(try event(.leftMouseDragged, at: inside, number: 3)) }
        queued.append(try event(.leftMouseUp, at: reenter ? inside : outside, number: 4))
        for next in queued.reversed() { NSApp.postEvent(next, atStart: true) }
        NSApp.sendEvent(try event(.leftMouseDown, at: inside, number: 1))
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                         until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(next)
        }
    }
}

// Keep the README's complete public integration example compiling here.
private struct WindowButtons: View {
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onZoom: () -> Void

    var body: some View {
        TrafficLightGroup {
            TrafficLightButton(.close, action: onClose)
            TrafficLightButton(.minimize, action: onMinimize)
            TrafficLightButton(.zoom, action: onZoom)
        }
    }
}

private final class StateWindow: NSWindow {
    var reportsKey = false
    override var isKeyWindow: Bool { reportsKey }
}
