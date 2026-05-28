//
//  MultitaskUpgradeSheet.swift
//  Turbotask
//

import SwiftUI

struct MultitaskUpgradeOffer: Identifiable, Equatable {
    let id: UUID
    /// Tasks that will run in parallel after confirming (current actives + the one being started).
    var participants: [Participant]
    var targetEnergy: TaskEnergy
    var incomingTaskID: UUID

    struct Participant: Identifiable, Equatable {
        var id: UUID { taskID }
        let taskID: UUID
        let title: String
        let currentEnergyLabel: String
    }
}

struct MultitaskUpgradeSheet: View {
    @EnvironmentObject private var store: TurboTaskStore
    let offer: MultitaskUpgradeOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run these together?")
                .font(.headline)
                .foregroundStyle(TurboTheme.ink)

            Text(
                "They aren’t compatible as-is. To keep every task in progress, Turbo can set the work type to \(offer.targetEnergy.title) (\(offer.targetEnergy.shortTitle)) for all of them."
            )
            .font(.subheadline)
            .foregroundStyle(TurboTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(offer.participants) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(TurboTheme.accentSoft)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TurboTheme.ink)
                                .lineLimit(2)
                            Text("Now: \(p.currentEnergyLabel)")
                                .font(.caption)
                                .foregroundStyle(TurboTheme.mutedInk)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TurboTheme.nestedCardFill.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                Button("Cancel") {
                    store.cancelMultitaskUpgradeOffer()
                }
                .keyboardShortcut(.cancelAction)

                Button("Switch to new task only") {
                    store.confirmMultitaskUpgradeSwitchOnly()
                }
                .help("Pause other in-progress tasks and start only the one you picked.")

                Spacer(minLength: 8)

                Button("Run together as \(offer.targetEnergy.shortTitle)") {
                    store.confirmMultitaskUpgrade()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 440)
    }
}
