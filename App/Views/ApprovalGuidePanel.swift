import AppKit
import SwiftUI

/// A small floating, non-activating panel that points at the "Allow in the Background" switch
/// while System Settings is open. Closed by the model once the helper is enabled.
@MainActor
final class ApprovalGuidePanel {
    private var panel: NSPanel?
    private var placement: Task<Void, Never>?
    private static let size = NSSize(width: 320, height: 140)

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .hudWindow],
                            backing: .buffered, defer: false)
        panel.title = "Boreas"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ApprovalGuideView())
        panel.setFrameOrigin(Self.defaultOrigin())
        panel.orderFrontRegardless()
        self.panel = panel

        // System Settings needs a moment to put its window up; look for it a few times.
        placement = Task { [weak self] in
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                if let origin = Self.originNextToSystemSettings() {
                    self?.panel?.setFrameOrigin(origin)
                    return
                }
            }
        }
    }

    func close() {
        placement?.cancel()
        placement = nil
        panel?.close()
        panel = nil
    }

    /// Right of the screen's centre.
    private static func defaultOrigin() -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let x = Swift.min(frame.midX + 300, frame.maxX - size.width - 12)
        return NSPoint(x: x, y: frame.midY - size.height / 2)
    }

    /// Next to the System Settings window, found through the window list (bounds and owner name
    /// need no extra permission). nil when it is not on screen or there is no room beside it.
    private static func originNextToSystemSettings() -> NSPoint? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let candidates = list.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerName as String] as? String == "System Settings",
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.width > 200 else { return nil }
            return rect
        }
        guard let cg = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        // CG: origin top-left of the primary display; AppKit: bottom-left.
        let window = CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }
        let x = window.maxX + 12
        guard x + size.width <= visible.maxX else { return nil }
        let y = Swift.min(Swift.max(window.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

private struct ApprovalGuideView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            Text("Turn on Boreas under “Allow in the Background”")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320, height: 140)
    }
}
