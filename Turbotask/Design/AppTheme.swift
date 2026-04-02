//
//  AppTheme.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
import SwiftUI

enum TurboTheme {
    /// Neutral canvas (Cursor-style dark: balanced grays, no blue cast).
    static let background = Color.turbo(
        light: NSColor(white: 0.965, alpha: 1),
        dark: NSColor(white: 0.090, alpha: 1)
    )
    static let backgroundRaised = Color.turbo(
        light: NSColor(white: 1.0, alpha: 1),
        dark: NSColor(white: 0.118, alpha: 1)
    )
    static let sidebar = Color.turbo(
        light: NSColor(white: 0.936, alpha: 1),
        dark: NSColor(white: 0.076, alpha: 1)
    )
    static let cardFill = Color.turbo(
        light: NSColor(white: 1.0, alpha: 1),
        dark: NSColor(white: 0.128, alpha: 1)
    )
    static let nestedCardFill = Color.turbo(
        light: NSColor(white: 0.965, alpha: 1),
        dark: NSColor(white: 0.148, alpha: 1)
    )
    static let cardStroke = Color.turbo(
        light: NSColor(white: 0.878, alpha: 1),
        dark: NSColor(white: 0.248, alpha: 1)
    )
    static let divider = Color.turbo(
        light: NSColor(white: 0.898, alpha: 1),
        dark: NSColor(white: 0.208, alpha: 1)
    )
    static let ink = Color.turbo(
        light: NSColor(white: 0.082, alpha: 1),
        dark: NSColor(white: 0.914, alpha: 1)
    )
    static let mutedInk = Color.turbo(
        light: NSColor(white: 0.455, alpha: 1),
        dark: NSColor(white: 0.540, alpha: 1)
    )
    static let sidebarInk = Color.turbo(
        light: NSColor(white: 0.118, alpha: 1),
        dark: NSColor(white: 0.835, alpha: 1)
    )
    /// Sidebar list row label when that row is selected (List uses `accent` as the selection fill).
    static let sidebarSelectionInk = Color.turbo(
        light: NSColor(white: 0.98, alpha: 1),
        dark: NSColor(white: 0.10, alpha: 1)
    )
    /// App control tint (sidebar selection, pickers, focus) — neutral, not system blue.
    static let accent = Color.turbo(
        light: NSColor(white: 0.10, alpha: 1),
        dark: NSColor(white: 0.86, alpha: 1)
    )
    static let accentSoft = Color.turbo(
        light: NSColor(white: 0.898, alpha: 1),
        dark: NSColor(white: 0.182, alpha: 1)
    )
    static let rowHover = Color.turbo(
        light: NSColor(white: 0.945, alpha: 1),
        dark: NSColor(white: 0.162, alpha: 1)
    )
    static let rowSelected = Color.turbo(
        light: NSColor(white: 0.925, alpha: 1),
        dark: NSColor(white: 0.202, alpha: 1)
    )
    static let slate = Color.turbo(
        light: NSColor(white: 0.455, alpha: 1),
        dark: NSColor(white: 0.588, alpha: 1)
    )
    static let waiting = Color.turbo(
        light: NSColor(white: 0.38, alpha: 1),
        dark: NSColor(white: 0.62, alpha: 1)
    )
    static let warning = Color.turbo(
        light: NSColor(red: 0.98, green: 0.52, blue: 0.06, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.62, blue: 0.22, alpha: 1)
    )
    static let danger = Color.turbo(
        light: NSColor(red: 0.94, green: 0.18, blue: 0.28, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.38, blue: 0.42, alpha: 1)
    )
    static let overlayFill = Color.turbo(
        light: NSColor(white: 0.996, alpha: 0.94),
        dark: NSColor(white: 0.082, alpha: 0.94)
    )
    static let shadow = Color.turbo(
        light: NSColor(white: 0.0, alpha: 0.06),
        dark: NSColor(white: 0.0, alpha: 0.45)
    )
}

extension View {
    func turboCard(
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 10
    ) -> some View {
        self
            .padding(padding)
            .foregroundStyle(TurboTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TurboTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(TurboTheme.cardStroke, lineWidth: 1)
                    )
            )
    }

    func turboPanel(cornerRadius: CGFloat = 8) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1)
                )
        )
    }
}

private extension Color {
    static func turbo(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
            case .darkAqua, .vibrantDark:
                dark
            default:
                light
            }
        })
    }
}
