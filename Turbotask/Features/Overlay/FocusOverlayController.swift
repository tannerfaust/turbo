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
    private weak var boundStore: TurboTaskStore?
    private var moveObserver: NSObjectProtocol?
    private var persistWorkItem: DispatchWorkItem?
    private var resizeWorkItem: DispatchWorkItem?
    private var pendingContentSize: CGSize?

    func show(store: TurboTaskStore) {
        boundStore = store
        let creatingNewPanel = (panel == nil)
        let panel = panel ?? makePanel(store: store)
        let frameBeforeContentSwap = panel.frame

        let needsHostingView = creatingNewPanel || panel.contentView == nil
        if needsHostingView {
            panel.contentView = makeHostingView(store: store)
        }
        panel.appearance = appearance(for: store.themeMode)
        applyPresenceMode(store.focusOverlayPresenceMode, panel: panel)
        installFrameTracking(for: panel, store: store)

        let defaultSize = NSSize(width: 240, height: 200)
        let frame = resolveFrame(
            desiredSize: defaultSize,
            store: store,
            creatingNewPanel: creatingNewPanel,
            frameBeforeContentSwap: frameBeforeContentSwap
        )
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        schedulePersistCurrentFrame(store: store)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// SwiftUI reports measured content size so the panel is not clipped. Keeps the top edge fixed so the card does not jump.
    func noteContentSize(_ size: CGSize, store: TurboTaskStore) {
        boundStore = store
        pendingContentSize = size
        resizeWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self, weak store] in
            guard let self, let store, let panel = self.panel, let pendingContentSize = self.pendingContentSize else { return }
            let nss = NSSize(width: max(pendingContentSize.width, 120), height: max(pendingContentSize.height, 72))
            let newFrame = self.clampFrameToScreens(self.topAnchoredResize(panel.frame, to: nss))
            guard !newFrame.equalTo(panel.frame) else { return }
            panel.setFrame(newFrame, display: false)
            self.schedulePersistCurrentFrame(store: store)
        }

        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Updates Spaces / desktop behavior while the panel exists (and re-orders it forward if visible).
    func applyPresenceMode(_ mode: FocusOverlayPresenceMode) {
        guard let panel else { return }
        applyPresenceMode(mode, panel: panel)
    }

    private func resolveFrame(
        desiredSize: NSSize,
        store: TurboTaskStore,
        creatingNewPanel: Bool,
        frameBeforeContentSwap: NSRect
    ) -> NSRect {
        if !creatingNewPanel {
            return clampFrameToScreens(topAnchoredResize(frameBeforeContentSwap, to: desiredSize))
        }
        if let saved = store.focusOverlayWindowFrame {
            let top = CGFloat(saved.y + saved.height)
            let origin = NSPoint(x: CGFloat(saved.x), y: top - desiredSize.height)
            return clampFrameToScreens(NSRect(origin: origin, size: desiredSize))
        }
        return clampFrameToScreens(topRightFrame(size: desiredSize))
    }

    private func topAnchoredResize(_ frame: NSRect, to newSize: NSSize) -> NSRect {
        let top = frame.maxY
        return NSRect(x: frame.origin.x, y: top - newSize.height, width: newSize.width, height: newSize.height)
    }

    private func topRightFrame(size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 24
        )
        return NSRect(origin: origin, size: size)
    }

    private func clampFrameToScreens(_ rect: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return rect }
        var union = screens[0].visibleFrame
        for s in screens.dropFirst() {
            union = union.union(s.visibleFrame)
        }
        if !rect.intersects(union) {
            return topRightFrame(size: rect.size)
        }
        var r = rect
        r.origin.x = min(max(r.origin.x, union.minX), union.maxX - r.width)
        r.origin.y = min(max(r.origin.y, union.minY), union.maxY - r.height)
        return r
    }

    private func installFrameTracking(for panel: NSPanel, store: TurboTaskStore) {
        removeFrameTracking()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self, weak store] in
                guard let self, let store else { return }
                self.schedulePersistCurrentFrame(store: store)
            }
        }
    }

    private func removeFrameTracking() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil
    }

    private func schedulePersistCurrentFrame(store: TurboTaskStore) {
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            store.recordFocusOverlayWindowFrame(panel.frame)
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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
        applyPresenceMode(store.focusOverlayPresenceMode, panel: panel)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = appearance(for: store.themeMode)

        self.panel = panel
        return panel
    }

    private func applyPresenceMode(_ mode: FocusOverlayPresenceMode, panel: NSPanel) {
        switch mode {
        case .allDesktops:
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .thisDesktopOnly:
            panel.collectionBehavior = [.fullScreenAuxiliary]
        }
        if panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makeHostingView(store: TurboTaskStore) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(
            FocusOverlayView()
                .environmentObject(store)
                .environment(\.trainingWheelsEnabled, store.trainingWheelsEnabled)
                .tint(TurboTheme.accent)
        ))
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
