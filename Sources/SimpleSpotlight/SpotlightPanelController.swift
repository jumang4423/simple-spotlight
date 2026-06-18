import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class SpotlightPanelController: NSObject, NSWindowDelegate {
    private let viewModel: SpotlightViewModel
    private lazy var panel: KeyablePanel = makePanel()
    private var isAnimating = false

    init(viewModel: SpotlightViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func toggle() {
        guard !isAnimating else { return }
        if panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard !panel.isVisible else { return }
        viewModel.reset()
        viewModel.requestFocus()
        NSApp.activate(ignoringOtherApps: true)

        let finalFrame = centeredFrame()
        panel.setFrame(finalFrame.insetBy(dx: 10, dy: 7), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.alphaValue = 1
                self?.panel.setFrame(finalFrame, display: true)
                self?.isAnimating = false
            }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        let currentFrame = panel.frame
        let finalFrame = currentFrame.insetBy(dx: 8, dy: 6)

        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.setFrame(currentFrame, display: false)
                self.isAnimating = false
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> KeyablePanel {
        let rootView = SpotlightView(viewModel: viewModel) { [weak self] in
            self?.close()
        }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 330),
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

    private func centeredFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2 + 120
        )
        return NSRect(origin: origin, size: size)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
