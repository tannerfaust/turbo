//
//  FocusOverlayPresenceMode.swift
//  Turbotask
//

import Foundation

/// Where the floating focus card participates in macOS Spaces (Mission Control desktops).
enum FocusOverlayPresenceMode: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Window uses `canJoinAllSpaces` — visible when switching to any desktop.
    case allDesktops
    /// Window stays on the Space where it was shown; does not follow across desktops.
    case thisDesktopOnly

    var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .allDesktops:
            "All desktops"
        case .thisDesktopOnly:
            "This desktop only"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .allDesktops:
            "Follows you when you switch Mission Control desktops."
        case .thisDesktopOnly:
            "Stays on the desktop where the card is open."
        }
    }

    var menuTitle: String {
        switch self {
        case .allDesktops:
            "Show on all desktops"
        case .thisDesktopOnly:
            "This desktop only"
        }
    }

    var menuSubtitle: String {
        switch self {
        case .allDesktops:
            "Visible in every Space"
        case .thisDesktopOnly:
            "Not on other Spaces"
        }
    }
}
