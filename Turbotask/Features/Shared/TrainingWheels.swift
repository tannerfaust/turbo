//
//  TrainingWheels.swift
//  Turbotask
//
//  Linear-style interactive keyboard hints with styled key badges.
//

import SwiftUI

// MARK: - Key badge (styled keycap)

struct KeyBadge: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(TurboTheme.ink.opacity(0.78))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(TurboTheme.nestedCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(TurboTheme.divider.opacity(0.9), lineWidth: 0.5)
                    )
                    .shadow(color: TurboTheme.ink.opacity(0.06), radius: 0.5, y: 0.5)
            )
    }
}

// MARK: - Inline hint (appears below controls)

struct TrainingWheelsHint: View {
    @Environment(\.trainingWheelsEnabled) private var enabled
    let text: String

    var body: some View {
        if enabled {
            TrainingWheelsRichLine(text: text)
        }
    }
}

/// Parses "text · ⌘D done · Esc" into mixed Text + KeyBadge segments.
struct TrainingWheelsRichLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(parseSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let str):
                    Text(str)
                        .font(.caption2)
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.75))
                case .key(let key):
                    KeyBadge(key: key)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum Segment {
        case text(String)
        case key(String)
    }

    private func parseSegments(_ raw: String) -> [Segment] {
        let keyPatterns: Set<String> = [
            "⌘", "⇧", "⌃", "⌥", "Esc", "Return", "↩", "Tab",
            "↑", "↓", "←", "→", "Delete", "Space"
        ]

        let parts = raw.split(separator: "·", omittingEmptySubsequences: false)
        var result: [Segment] = []

        for (idx, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if idx > 0 { result.append(.text("·")) }
                continue
            }

            let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            var hasKey = false
            for word in words {
                let w = String(word)
                if looksLikeShortcut(w, patterns: keyPatterns) {
                    if hasKey { result.append(.text(" ")) }
                    result.append(.key(w))
                    hasKey = true
                } else {
                    if hasKey { result.append(.text(" ")) }
                    result.append(.text(w))
                    hasKey = true
                }
            }

            if idx < parts.count - 1 {
                result.append(.text(" · "))
            }
        }

        return result
    }

    private func looksLikeShortcut(_ word: String, patterns: Set<String>) -> Bool {
        if patterns.contains(word) { return true }
        if word.count <= 5, word.unicodeScalars.contains(where: { patterns.contains(String($0)) }) {
            return true
        }
        if word.hasPrefix("⌘") || word.hasPrefix("⇧") || word.hasPrefix("⌃") || word.hasPrefix("⌥") {
            return true
        }
        return false
    }
}

// MARK: - Environment key (avoids subscribing every tooltip to full store changes)

struct TrainingWheelsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var trainingWheelsEnabled: Bool {
        get { self[TrainingWheelsEnabledKey.self] }
        set { self[TrainingWheelsEnabledKey.self] = newValue }
    }
}

// MARK: - Tooltip modifier (hover help tags)

private struct TrainingWheelsTooltipModifier: ViewModifier {
    @Environment(\.trainingWheelsEnabled) private var enabled
    let text: String

    func body(content: Content) -> some View {
        if enabled {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    func trainingWheelsTooltip(_ text: String) -> some View {
        modifier(TrainingWheelsTooltipModifier(text: text))
    }
}

// MARK: - Floating shortcut discovery bar

struct ShortcutDiscoveryBar: View {
    @Environment(\.trainingWheelsEnabled) private var enabled

    let shortcuts: [(keys: String, label: String)]

    var body: some View {
        if enabled {
            HStack(spacing: 12) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 4) {
                        KeyBadge(key: entry.keys)
                        Text(entry.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(TurboTheme.mutedInk.opacity(0.72))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(TurboTheme.nestedCardFill.opacity(0.85))
                    .overlay(
                        Capsule()
                            .stroke(TurboTheme.divider.opacity(0.55), lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Context-aware shortcut bar for each screen

struct ScreenShortcutBar: View {
    @Environment(\.trainingWheelsEnabled) private var enabled
    let screen: TurboTaskStore.Screen

    var body: some View {
        if enabled {
            let shortcuts = shortcutsForScreen(screen)
            if !shortcuts.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 4) {
                            KeyBadge(key: entry.keys)
                            Text(entry.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TurboTheme.mutedInk.opacity(0.68))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Rectangle()
                        .fill(TurboTheme.nestedCardFill.opacity(0.45))
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TurboTheme.divider.opacity(0.35))
                        .frame(height: 1)
                }
            }
        }
    }

    private func shortcutsForScreen(_ screen: TurboTaskStore.Screen) -> [(keys: String, label: String)] {
        switch screen {
        case .now:
            return [
                ("↑↓", "Select"),
                ("↩", "Start"),
                ("⌘D", "Done"),
                ("⌘P", "Pause"),
                ("⌘N", "Quick add"),
                ("⌘E", "Edit"),
                ("⇧⌘F", "Focus card"),
                ("⇧⌘L", "List / Kanban / tree"),
                ("Drag", "Reorder or move columns"),
            ]
        case .projects:
            return [
                ("←→", "Switch field"),
                ("↑↓", "Select project"),
                ("⇧⌘P", "New project"),
                ("⌘T", "New task"),
                ("Drag", "Reorder"),
            ]
        case .tasks:
            return [
                ("⌘T", "New task"),
                ("↑↓", "Select"),
                ("↩", "Edit"),
                ("⌘D", "Done"),
                ("⌘P", "Pause"),
                ("⌃⌘1-5", "Set status"),
                ("Drag", "Kanban columns"),
            ]
        case .jobs:
            return [
                ("↑↓", "Select field"),
                ("↩", "Pick field"),
                ("⇧⌘J", "New field"),
                ("⌘T", "New task"),
            ]
        case .metrics:
            return [
                ("⌘1-6", "Main screens"),
                ("⌘7", "Archive"),
            ]
        case .battery:
            return [
                ("⌘6", "This screen"),
                ("⌘7", "Archive"),
            ]
        case .archive:
            return [
                ("Double-click", "Edit task"),
                ("Two-finger click", "Restore, delete, edit"),
                ("⌘7", "This screen"),
            ]
        case .settings:
            return [
                ("⌘Z", "Undo"),
                ("⌘1-7", "Navigate"),
            ]
        }
    }
}
