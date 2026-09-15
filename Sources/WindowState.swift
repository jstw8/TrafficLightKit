import AppKit
import SwiftUI

@MainActor
final class WindowState: NSObject, ObservableObject {
    @Published private(set) var isKey = false

    private weak var window: NSWindow?

    func attach(to window: NSWindow?) {
        guard window !== self.window else { return }

        NotificationCenter.default.removeObserver(self)
        self.window = window

        // Updating ObservableObject state during a representable update emits
        // SwiftUI's in-update publishing warning, so read on the next turn.
        Task { @MainActor [weak self] in self?.refresh() }

        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyStateDidChange),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyStateDidChange),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    @objc private func keyStateDidChange() {
        refresh()
    }

    private func refresh() {
        let next = window?.isKeyWindow ?? false
        if isKey != next { isKey = next }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct WindowStateReader: NSViewRepresentable {
    let state: WindowState

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.state = state
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.state = state
        view.attachIfPossible()
    }

    final class ReaderView: NSView {
        var state: WindowState?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfPossible()
        }

        func attachIfPossible() {
            state?.attach(to: window)
        }
    }
}
