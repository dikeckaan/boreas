import AppKit
import SwiftUI

extension View {
    /// Keeps `isVisible` in step with whether the hosting window can actually be seen: not closed,
    /// not minimised, not fully covered and on the current Space.
    ///
    /// SwiftUI keeps a closed or hidden `Window` scene's view tree alive and re-renders it on every
    /// model change. With the history chart that means a full redraw every second nobody sees, and
    /// SwiftUI's renderer piles up surface-pool timers for it (about one per second, never freed),
    /// which is how the app grew to gigabytes over a few days. Views gate their content on this.
    func trackWindowVisibility(_ isVisible: Binding<Bool>) -> some View {
        background(WindowVisibilityReader(isVisible: isVisible).frame(width: 0, height: 0))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> WindowVisibilityView {
        let view = WindowVisibilityView()
        view.onChange = { visible in isVisible = visible }
        return view
    }

    func updateNSView(_ view: WindowVisibilityView, context: Context) {
        view.onChange = { visible in isVisible = visible }
    }
}

final class WindowVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private weak var observed: NSWindow?
    private var reported: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        if let observed {
            center.removeObserver(self, name: nil, object: observed)
        }
        observed = window
        guard let window else { return }
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: window)
        }
        report(Self.isShowing(window))
    }

    @objc private func windowChanged(_ note: Notification) {
        guard let window = observed else { return }
        report(note.name == NSWindow.willCloseNotification ? false : Self.isShowing(window))
    }

    private static func isShowing(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    private func report(_ visible: Bool) {
        guard visible != reported else { return }
        reported = visible
        // Never change SwiftUI state in the middle of a view update.
        DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
    }
}
