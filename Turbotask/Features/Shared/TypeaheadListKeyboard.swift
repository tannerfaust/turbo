//
//  TypeaheadListKeyboard.swift
//  Turbotask
//
//  Arrow + Return navigation for filtered lists while the search field is focused (Linear-style).
//

import AppKit
import Combine
import SwiftUI

/// Shared highlight index for type-ahead keyboard navigation.
@MainActor
final class TypeaheadRowHighlight: ObservableObject {
    @Published var index: Int = 0

    func reset() {
        index = 0
    }

    func move(by delta: Int, count: Int) {
        guard count > 0 else { return }
        index = min(max(0, index + delta), count - 1)
    }

    func clamp(count: Int) {
        guard count > 0 else {
            index = 0
            return
        }
        index = min(index, count - 1)
    }
}

/// Holds the current list length for arrow-key navigation. Event monitors should read this instead of capturing SwiftUI-derived counts, which can go stale inside escaping closures.
@MainActor
final class TypeaheadLiveCount: ObservableObject {
    @Published var value: Int = 0
}

enum TypeaheadListKeyboard {
    /// Local monitor: ↑/↓ move highlight, Return activates (without ⌘). Returns opaque token for `remove`.
    @MainActor
    static func install(
        store: TurboTaskStore,
        isSearchFocused: @escaping () -> Bool,
        itemCount: @escaping () -> Int,
        highlight: TypeaheadRowHighlight,
        onActivate: @escaping (Int) -> Void
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Thread.isMainThread else { return event }
            guard store.typeaheadListNavigationEnabled else { return event }
            guard isSearchFocused() else { return event }
            let count = itemCount()
            guard count > 0 else { return event }

            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch code {
            case 125: // down
                highlight.move(by: 1, count: count)
                return nil
            case 126: // up
                highlight.move(by: -1, count: count)
                return nil
            case 36: // return
                if flags.contains(.command) { return event }
                onActivate(highlight.index)
                return nil
            default:
                return event
            }
        }
    }

    static func remove(_ token: Any?) {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }
}
