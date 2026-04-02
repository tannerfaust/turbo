//
//  TrainingWheels.swift
//  Turbotask
//
//  Linear-style inline keyboard hints (toggle in Settings).
//

import SwiftUI

struct TrainingWheelsHint: View {
    @EnvironmentObject private var store: TurboTaskStore
    let text: String

    var body: some View {
        if store.trainingWheelsEnabled {
            Text(text)
                .font(.caption2)
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// macOS tooltip on hover when “training wheels” is on (Settings → Keyboard & learning).
private struct TrainingWheelsTooltipModifier: ViewModifier {
    @EnvironmentObject private var store: TurboTaskStore
    let text: String

    func body(content: Content) -> some View {
        if store.trainingWheelsEnabled {
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
