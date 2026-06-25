//
//  WindowTitleBarController.swift
//  Turbotask
//

import AppKit
import SwiftUI

/// Keeps the macOS window title in sync with in-app navigation (e.g. sticky "Now").
struct WindowTitleBarController: NSViewRepresentable {
    var title: String
    var isHidden: Bool

    func makeNSView(context: Context) -> TitleTrackingView {
        let view = TitleTrackingView()
        view.apply = { window in
            apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: TitleTrackingView, context: Context) {
        nsView.apply = { window in
            apply(to: window)
        }
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        if isHidden {
            window.titleVisibility = .hidden
            window.title = ""
        } else {
            window.titleVisibility = .visible
            window.title = title
        }
    }
}

final class TitleTrackingView: NSView {
    var apply: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply?(window)
    }
}

struct NowTitleCollapsePreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}
