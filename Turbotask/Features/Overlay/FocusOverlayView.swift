//
//  FocusOverlayView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

private struct FocusCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.height > 0, next.width > 0 {
            value = next
        }
    }
}

struct FocusOverlayView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var lastReportedSize: CGSize = .zero
    @State private var editingTask: TaskContext?

    private var density: FocusCardDensity {
        store.focusCardDensity
    }

    private var focusTasks: [TaskContext] {
        store.currentFocusGroup
    }

    private var isMultitaskBundle: Bool {
        focusTasks.count > 1
    }

    private var cardWidth: CGFloat {
        switch density {
        case .standard:
            220
        case .compact:
            196
        case .minimal:
            168
        }
    }

    private var cardPadding: CGFloat {
        switch density {
        case .standard:
            6
        case .compact:
            5
        case .minimal:
            4
        }
    }

    private var scrollMaxHeight: CGFloat {
        switch density {
        case .standard:
            88
        case .compact:
            64
        case .minimal:
            48
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            if focusTasks.isEmpty {
                emptyState
            } else {
                taskSection
            }
        }
        .padding(cardPadding)
        .frame(width: cardWidth, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        .background(cardChrome)
        .overlay(sizeMeasureLayer)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(TurboTheme.cardStroke.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .onPreferenceChange(FocusCardSizeKey.self) { size in
            guard size.width > 1, size.height > 1 else { return }
            let dw = abs(size.width - lastReportedSize.width)
            let dh = abs(size.height - lastReportedSize.height)
            guard dw > 1.5 || dh > 1.5 else { return }
            lastReportedSize = size
            DispatchQueue.main.async {
                FocusOverlayController.shared.noteContentSize(size)
            }
        }
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
                .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
    }

    private var sizeMeasureLayer: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: FocusCardSizeKey.self, value: proxy.size)
        }
    }

    private var cardChrome: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(TurboTheme.cardFill.opacity(0.22))
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Focus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .tracking(0.2)
            Spacer(minLength: 4)

            Menu {
                ForEach(FocusCardDensity.allCases) { option in
                    Button {
                        store.focusCardDensity = option
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.menuTitle)
                                Text(option.menuSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if store.focusCardDensity == option {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(TurboTheme.mutedInk.opacity(0.55))
            .fixedSize()
            .trainingWheelsTooltip("Resize focus card: standard, compact, or minimal")

            Button {
                store.toggleOverlay()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(TurboTheme.mutedInk.opacity(0.5))
            .trainingWheelsTooltip("Hide focus card · ⇧⌘F")
        }
        .padding(.bottom, density == .minimal ? 3 : 4)
    }

    @ViewBuilder
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: density == .minimal ? 3 : 4) {
            if isMultitaskBundle, density == .standard {
                Text("Together")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.72))
            }

            Group {
                if focusTasks.count > 3 {
                    ScrollView {
                        focusTaskList
                    }
                    .frame(maxHeight: scrollMaxHeight)
                } else {
                    focusTaskList
                }
            }
            .padding(.vertical, density == .minimal ? 1 : 2)
            .padding(.horizontal, 1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TurboTheme.nestedCardFill.opacity(density == .minimal ? 0.35 : 0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TurboTheme.cardStroke.opacity(0.28), lineWidth: 1)
                    )
            )

            if density == .standard, let next = store.nextTask {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Next")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.6))
                    Text(next.task.title)
                        .font(.system(size: 9))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var focusTaskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(focusTasks.enumerated()), id: \.element.id) { _, context in
                FocusOverlayTaskRow(context: context, density: density, onEdit: { editingTask = context })
                if context.task.id != focusTasks.last?.task.id {
                    Rectangle()
                        .fill(TurboTheme.divider.opacity(0.35))
                        .frame(height: 1)
                        .padding(.leading, density == .minimal ? 0 : 14)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: density == .minimal ? 2 : 3) {
            Text("Nothing in progress")
                .font(density == .minimal ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(TurboTheme.ink.opacity(0.85))
            if density != .minimal {
                Text("Start from Now.")
                    .font(.system(size: 9))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .padding(.vertical, density == .minimal ? 2 : 4)
    }
}

// MARK: - Row

private struct FocusOverlayTaskRow: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    let density: FocusCardDensity
    let onEdit: () -> Void

    private var isActive: Bool {
        context.task.status == .active
    }

    var body: some View {
        Group {
            switch density {
            case .minimal:
                minimalRow
            case .compact:
                compactRow
            case .standard:
                standardRow
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEdit)
                .environmentObject(store)
        }
    }

    private var minimalRow: some View {
        HStack(alignment: .center, spacing: 5) {
            TaskStatusRowIndicator(
                status: context.task.status,
                jobColor: context.jobColor,
                diameter: 10
            )

            Text(context.task.title)
                .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                .foregroundStyle(TurboTheme.ink)
                .lineLimit(1)

            Text(context.task.energy.shortTitle)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(context.task.energy.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(context.task.energy.accent.opacity(0.12))
                )
                .fixedSize()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 3)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(context.jobColor.opacity(0.9))
                .frame(width: 2, height: 20)

            TaskStatusRowIndicator(
                status: context.task.status,
                jobColor: context.jobColor,
                diameter: 14
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(context.task.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)

                Text(context.task.energy.shortTitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(context.task.energy.accent.opacity(0.95))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(context.task.energy.accent.opacity(0.11))
                    )
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private var standardRow: some View {
        HStack(alignment: .center, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(context.jobColor.opacity(0.9))
                .frame(width: 2, height: 22)

            TaskStatusRowIndicator(
                status: context.task.status,
                jobColor: context.jobColor,
                diameter: 16
            )

            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.task.title)
                        .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(rowSubtitle)
                        .font(.system(size: 8))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(context.task.energy.shortTitle)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(context.task.energy.accent.opacity(0.95))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(context.task.energy.accent.opacity(0.12))
                            )

                        Text(focusScopeLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(TurboTheme.mutedInk.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !context.task.toolBundleIDs.isEmpty {
                    TaskToolsIconRow(bundleIDs: context.task.toolBundleIDs, iconSize: 11, maxIcons: 4)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private var rowSubtitle: String {
        let step = context.task.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if let waiting = context.task.waitingOn?.trimmingCharacters(in: .whitespacesAndNewlines), !waiting.isEmpty {
            return waiting
        }
        if !step.isEmpty {
            return step
        }
        let parts = context.metaSubtitleParts
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var focusScopeLabel: String {
        if !context.projectTitle.isEmpty { return context.projectTitle }
        if !context.jobTitle.isEmpty { return context.jobTitle }
        return "Inbox"
    }
}
