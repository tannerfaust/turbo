//
//  FocusCardDensity.swift
//  Turbotask
//

import Foundation

/// How much detail the floating focus card shows.
enum FocusCardDensity: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Current default: titles, hints, progress, next task, tools when present.
    case standard
    /// Tighter type, hides secondary lines and tool strip.
    case compact
    /// Single line feel: task name and energy/type only.
    case minimal

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .standard:
            "Standard"
        case .compact:
            "Compact"
        case .minimal:
            "Minimal (name & type)"
        }
    }

    var menuSubtitle: String {
        switch self {
        case .standard:
            "Full detail"
        case .compact:
            "Less info, smaller"
        case .minimal:
            "Title and type only"
        }
    }
}
