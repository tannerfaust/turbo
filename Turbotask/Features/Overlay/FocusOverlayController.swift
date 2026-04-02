//
//  FocusOverlayController.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
import SwiftUI

@MainActor
final class FocusOverlayController {
    static let shared = FocusOverlayController()

    private var panel: NSPanel?

    func show(store: TurboTaskStore) {
        let panel = panel ?? makePanel(store: store)
        panel.contentView = makeHostingView(store: store)
        panel.appearance = appearance(for: store.themeMode)
        let fit = panel.contentView?.fittingSize ?? NSSize(width: 240, height: 200)
        let size = NSSize(width: max(fit.width, 120), height: max(fit.height, 80))
        applyTopRightFrame(for: panel, size: size)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// SwiftUI reports measured content size so the panel is not clipped.
    func noteContentSize(_ size: CGSize) {
        guard let panel else { return }
        let nss = NSSize(width: max(size.width, 120), height: max(size.height, 72))
        applyTopRightFrame(for: panel, size: nss)
    }

    private func makePanel(store: TurboTaskStore) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = appearance(for: store.themeMode)

        self.panel = panel
        return panel
    }

    private func makeHostingView(store: TurboTaskStore) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(
            FocusOverlayView()
                .environmentObject(store)
                .tint(TurboTheme.accent)
        ))
    }

    private func applyTopRightFrame(for panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 24
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func appearance(for mode: AppThemeMode) -> NSAppearance? {
        switch mode {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
