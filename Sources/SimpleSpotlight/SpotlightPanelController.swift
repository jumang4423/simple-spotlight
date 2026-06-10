import AppKit
import SwiftUI

@MainActor
final class SpotlightPanelController: NSObject, NSWindowDelegate {
    private let viewModel: SpotlightViewModel
    private lazy var panel: KeyablePanel = makePanel()

    init(viewModel: SpotlightViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func toggle() {
        if panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        viewModel.reset()
        viewModel.requestFocus()
        NSApp.activate(ignoringOtherApps: true)
        centerPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> KeyablePanel {
        let rootView = SpotlightView(viewModel: viewModel) { [weak self] in
            self?.close()
        }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Simple Spotlight"
        panel.contentView = NSHostingView(rootView: rootView)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func centerPanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2 + 120
        )
        panel.setFrameOrigin(origin)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
