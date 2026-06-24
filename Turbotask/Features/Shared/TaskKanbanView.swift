//
//  TaskKanbanView.swift
//  Turbotask
//
//  Linear-style Kanban: primary columns + hidden status bundles on the right.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum TaskKanbanBoardMode {
    case now
    case registry
}

// MARK: - Layout

private enum TaskKanbanLayout {
    static let primaryColumns: [TaskStatus] = [.queued, .active, .done]
    static let optionalColumns: [TaskStatus] = [.waiting, .paused]

    static let columnWidth: CGFloat = 248
    static let bundleWidth: CGFloat = 52
    static let dependencyTint = Color(red: 0.52, green: 0.38, blue: 0.96)
}

private struct KanbanOptimisticPlacement: Equatable {
    let taskID: UUID
    let status: TaskStatus
    let columnOrder: [UUID]
}

// MARK: - Drag state

final class KanbanDragState: ObservableObject {
    @Published var draggedTaskID: UUID?
    @Published var hoverColumn: TaskStatus?
    @Published var hoverBeforeTaskID: UUID?
    @Published var hoverColumnEnd = false
    @Published var hoverHiddenBundle: TaskStatus?
    @Published var hoverLinkTargetID: UUID?
    @Published var isLinkingDrop = false

    func reset() {
        draggedTaskID = nil
        hoverColumn = nil
        hoverBeforeTaskID = nil
        hoverColumnEnd = false
        hoverHiddenBundle = nil
        hoverLinkTargetID = nil
        isLinkingDrop = false
    }

    func resetInstantly() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reset()
        }
    }
}

private func performInstantKanbanUpdate(_ update: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        update()
    }
}

// MARK: - Board

struct TaskKanbanBoard: View {
    @EnvironmentObject private var store: TurboTaskStore
    @StateObject private var drag = KanbanDragState()
    @AppStorage("kanban_revealed_optional_statuses") private var revealedStatusesRaw = ""
    @State private var optimisticPlacement: KanbanOptimisticPlacement?
    @State private var dragEndMonitor: Any?
    @State private var linkingKeyMonitor: Any?

    let tasks: [TaskContext]
    let mode: TaskKanbanBoardMode
    let onEditTask: (TaskContext) -> Void

    private var revealedOptionalStatuses: Set<TaskStatus> {
        Set(
            revealedStatusesRaw
                .split(separator: ",")
                .compactMap { TaskStatus(rawValue: String($0)) }
                .filter { TaskKanbanLayout.optionalColumns.contains($0) }
        )
    }

    private var visibleColumns: [TaskStatus] {
        var columns = TaskKanbanLayout.primaryColumns
        for status in TaskKanbanLayout.optionalColumns {
            if revealedOptionalStatuses.contains(status) || !tasks(in: status).isEmpty {
                columns.append(status)
            }
        }
        return columns
    }

    private var hiddenBundles: [TaskStatus] {
        TaskKanbanLayout.optionalColumns.filter { !visibleColumns.contains($0) }
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(visibleColumns) { status in
                            kanbanColumn(status: status, canCollapse: TaskKanbanLayout.optionalColumns.contains(status))
                        }

                        if !hiddenBundles.isEmpty {
                            hiddenBundlesRail
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .onAppear {
            installDragEndMonitor()
            if store.dependencyLinkingSourceTaskID != nil {
                installLinkingKeyMonitor()
            }
        }
        .onDisappear {
            removeDragEndMonitor()
            removeLinkingKeyMonitor()
        }
        .onChange(of: store.dependencyLinkingSourceTaskID) { _, sourceID in
            if sourceID != nil {
                installLinkingKeyMonitor()
            } else {
                removeLinkingKeyMonitor()
            }
        }
        .onChange(of: tasks) { _, _ in
            guard let placement = optimisticPlacement,
                  let current = tasks.first(where: { $0.task.id == placement.taskID }),
                  current.task.status == placement.status else { return }
            optimisticPlacement = nil
        }
        .overlay(alignment: .bottom) {
            if store.dependencyLinkingSourceTaskID != nil {
                DependencyLinkingHintBar()
                    .environmentObject(store)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            } else if drag.draggedTaskID != nil {
                kanbanDragHint
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
    }

    private var kanbanDragHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.caption.weight(.semibold))
            Text("Drop to move · Option-drop onto a card to link")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(TurboTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(TurboTheme.cardFill)
                .shadow(color: TurboTheme.shadow.opacity(0.35), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(TurboTheme.cardStroke.opacity(0.8), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    private var emptyMessage: String {
        switch mode {
        case .now:
            "No tasks in this scope."
        case .registry:
            "No tasks match your filters."
        }
    }

    private func boardTasks() -> [TaskContext] {
        guard let placement = optimisticPlacement else { return tasks }
        return tasks.map { context in
            guard context.task.id == placement.taskID else { return context }
            var updated = context
            updated.task.status = placement.status
            return updated
        }
    }

    private func tasks(in status: TaskStatus) -> [TaskContext] {
        let source = boardTasks()
        if let placement = optimisticPlacement, placement.status == status {
            let byID = Dictionary(uniqueKeysWithValues: source.map { ($0.task.id, $0) })
            return placement.columnOrder.compactMap { byID[$0] }
        }

        let slice = source.filter { context in
            if optimisticPlacement?.taskID == context.task.id { return false }
            return context.task.status == status
        }

        switch mode {
        case .now:
            return slice.sorted { $0.task.nowOrder < $1.task.nowOrder }
        case .registry:
            return slice
        }
    }

    private func revealColumn(_ status: TaskStatus) {
        guard TaskKanbanLayout.optionalColumns.contains(status) else { return }
        performInstantKanbanUpdate {
            var set = revealedOptionalStatuses
            set.insert(status)
            revealedStatusesRaw = set.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    private func collapseColumn(_ status: TaskStatus) {
        guard TaskKanbanLayout.optionalColumns.contains(status) else { return }
        performInstantKanbanUpdate {
            var set = revealedOptionalStatuses
            set.remove(status)
            revealedStatusesRaw = set.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    private func installDragEndMonitor() {
        removeDragEndMonitor()
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                guard drag.draggedTaskID != nil else { return }
                // Let performDrop run on the same mouse-up first; only treat as cancel if still dragging.
                DispatchQueue.main.async {
                    guard drag.draggedTaskID != nil else { return }
                    drag.resetInstantly()
                    optimisticPlacement = nil
                }
            }
            return event
        }
    }

    private func removeDragEndMonitor() {
        if let dragEndMonitor {
            NSEvent.removeMonitor(dragEndMonitor)
            self.dragEndMonitor = nil
        }
    }

    private func installLinkingKeyMonitor() {
        removeLinkingKeyMonitor()
        linkingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard store.dependencyLinkingSourceTaskID != nil else { return event }
            if event.keyCode == 53 { // Esc
                store.cancelDependencyLinking()
                return nil
            }
            return event
        }
    }

    private func removeLinkingKeyMonitor() {
        if let linkingKeyMonitor {
            NSEvent.removeMonitor(linkingKeyMonitor)
            self.linkingKeyMonitor = nil
        }
    }

    private func columnOrder(for status: TaskStatus, movingID: UUID, before targetID: UUID?) -> [UUID] {
        var ids = tasks(in: status).map(\.task.id).filter { $0 != movingID }
        if let targetID, let index = ids.firstIndex(of: targetID) {
            ids.insert(movingID, at: index)
        } else {
            ids.append(movingID)
        }
        return ids
    }

    private func applyDrop(movingID: UUID, status: TaskStatus, before targetID: UUID?) {
        let order = columnOrder(for: status, movingID: movingID, before: targetID)

        drag.resetInstantly()
        optimisticPlacement = KanbanOptimisticPlacement(
            taskID: movingID,
            status: status,
            columnOrder: order
        )

        DispatchQueue.main.async {
            let succeeded: Bool
            switch mode {
            case .now:
                if let targetID {
                    succeeded = store.reorderNowKanbanTask(movingTaskID: movingID, before: targetID)
                } else {
                    succeeded = store.moveNowKanbanTaskToColumnEnd(movingTaskID: movingID, status: status)
                }
            case .registry:
                if let targetID {
                    succeeded = store.reorderRegistryKanbanTask(movingTaskID: movingID, before: targetID)
                } else {
                    succeeded = store.moveRegistryKanbanTaskToColumn(movingTaskID: movingID, status: status)
                }
            }

            if !succeeded {
                optimisticPlacement = nil
            }
        }
    }

    private func applyDependencyLink(prerequisiteID: UUID, followUpID: UUID) {
        drag.resetInstantly()
        optimisticPlacement = nil
        DispatchQueue.main.async {
            _ = store.linkKanbanDependency(prerequisiteTaskID: prerequisiteID, followUpTaskID: followUpID)
        }
    }

    // MARK: Columns

    @ViewBuilder
    private func kanbanColumn(status: TaskStatus, canCollapse: Bool) -> some View {
        let columnTasks = tasks(in: status)
        let isHoverColumn = drag.hoverColumn == status && drag.hoverHiddenBundle == nil

        VStack(alignment: .leading, spacing: 0) {
            columnHeader(status: status, canCollapse: canCollapse && columnTasks.isEmpty)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(columnTasks) { context in
                        kanbanCard(context: context)
                            .overlay(alignment: .top) {
                                if drag.draggedTaskID != nil,
                                   drag.hoverHiddenBundle == nil,
                                   !drag.hoverColumnEnd,
                                   drag.hoverBeforeTaskID == context.task.id {
                                    KanbanDropLine()
                                }
                            }
                            .onDrop(
                                of: [.text],
                                delegate: KanbanCardDropDelegate(
                                    targetTaskID: context.task.id,
                                    columnStatus: status,
                                    drag: drag,
                                    onDrop: { movingID in
                                        applyDrop(movingID: movingID, status: status, before: context.task.id)
                                    },
                                    onLink: { prerequisiteID in
                                        applyDependencyLink(prerequisiteID: prerequisiteID, followUpID: context.task.id)
                                    }
                                )
                            )
                    }

                    columnDropTarget(status: status, isEmpty: columnTasks.isEmpty)

                    columnAddButton(status: status)
                }
                .padding(8)
            }
            .frame(minHeight: 100)
        }
        .frame(width: TaskKanbanLayout.columnWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHoverColumn ? TurboTheme.accentSoft.opacity(0.32) : TurboTheme.nestedCardFill.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isHoverColumn ? status.accent.opacity(0.42) : TurboTheme.cardStroke.opacity(0.6),
                    lineWidth: isHoverColumn ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if store.dependencyLinkingSourceTaskID != nil {
                store.cancelDependencyLinking()
            }
        }
        .onDrop(
            of: [.text],
            delegate: KanbanColumnDropDelegate(
                columnStatus: status,
                drag: drag,
                onDropToColumn: { movingID in
                    applyDrop(movingID: movingID, status: status, before: nil)
                }
            )
        )
    }

    private func columnHeader(status: TaskStatus, canCollapse: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.accent)
                .frame(width: 7, height: 7)
            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            if canCollapse {
                Button {
                    collapseColumn(status)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                .buttonStyle(.plain)
                .help("Hide column")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TurboTheme.cardFill.opacity(0.3))
    }

    private func columnAddButton(status: TaskStatus) -> some View {
        Button {
            store.openComposer(
                .task,
                scheduleForNow: mode == .now,
                preferredStatus: status
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(TurboTheme.mutedInk.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TurboTheme.cardFill.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(TurboTheme.divider.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("New task in \(status.title)")
    }

    @ViewBuilder
    private func columnDropTarget(status: TaskStatus, isEmpty: Bool) -> some View {
        let showLine = drag.draggedTaskID != nil
            && drag.hoverColumn == status
            && drag.hoverHiddenBundle == nil
            && drag.hoverColumnEnd

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: isEmpty ? [4, 3] : []))
            .foregroundStyle(TurboTheme.divider.opacity(isEmpty ? 0.85 : 0.3))
            .frame(maxWidth: .infinity)
            .frame(minHeight: isEmpty ? 48 : 20)
            .overlay(alignment: .top) {
                if showLine { KanbanDropLine() }
            }
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: KanbanColumnEndDropDelegate(
                    columnStatus: status,
                    drag: drag,
                    onDropToEnd: { movingID in
                        applyDrop(movingID: movingID, status: status, before: nil)
                    }
                )
            )
    }

    private var hiddenBundlesRail: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(TurboTheme.divider.opacity(0.5))
                .frame(width: 1)
                .padding(.vertical, 8)

            VStack(spacing: 8) {
                ForEach(hiddenBundles) { status in
                    hiddenBundle(status: status)
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 4)
        }
        .frame(width: TaskKanbanLayout.bundleWidth + 14)
    }

    private func hiddenBundle(status: TaskStatus) -> some View {
        let isHover = drag.hoverHiddenBundle == status

        return VStack(spacing: 5) {
            Circle()
                .fill(status.accent)
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHover ? TurboTheme.ink : TurboTheme.mutedInk)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 88)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHover ? status.accent.opacity(0.14) : TurboTheme.nestedCardFill.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHover ? status.accent.opacity(0.5) : TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onDrop(
            of: [.text],
            delegate: KanbanHiddenBundleDropDelegate(
                columnStatus: status,
                drag: drag,
                onDrop: { movingID in
                    revealColumn(status)
                    applyDrop(movingID: movingID, status: status, before: nil)
                }
            )
        )
        .accessibilityLabel("Drop to reveal \(status.title) column")
    }

    @ViewBuilder
    private func kanbanCard(context: TaskContext) -> some View {
        let isSelected = store.selection == .task(
            jobID: context.jobID,
            projectID: context.projectID,
            taskID: context.task.id
        )
        let isDragging = drag.draggedTaskID == context.task.id
        let linkingRole = store.linkingRole(for: context.task.id)
        let isLinking = store.dependencyLinkingSourceTaskID != nil

        let card = KanbanTaskCard(
            context: context,
            isSelected: isSelected,
            isDragging: isDragging,
            isLinkHoverTarget: drag.hoverLinkTargetID == context.task.id && drag.isLinkingDrop,
            linkingRole: linkingRole,
            onEdit: { onEditTask(context) },
            onSelect: {
                if isLinking {
                    if linkingRole == .validTarget {
                        store.completeDependencyLinking(prerequisiteID: context.task.id)
                    }
                } else {
                    store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
                }
            }
        )
        .environmentObject(store)
        .dependencyLinkingCard(taskID: context.task.id, accentTint: TaskKanbanLayout.dependencyTint)
        .opacity(isDragging ? 0.55 : 1)
        .scaleEffect(isDragging ? 0.98 : 1, anchor: .center)
        .zIndex(linkingRole == .source ? 2 : (linkingRole == .validTarget ? 1 : 0))

        if isLinking {
            card
        } else {
            card
                .onDrag {
                    performInstantKanbanUpdate {
                        optimisticPlacement = nil
                        drag.draggedTaskID = context.task.id
                    }
                    return NSItemProvider(object: context.task.id.uuidString as NSString)
                } preview: {
                    KanbanTaskCard(
                        context: context,
                        isSelected: false,
                        isDragging: false,
                        onEdit: {},
                        onSelect: {}
                    )
                    .environmentObject(store)
                    .frame(width: TaskKanbanLayout.columnWidth - 16)
                    .shadow(color: TurboTheme.shadow, radius: 10, y: 5)
                }
        }
    }
}

// MARK: - Card

private struct KanbanTaskCard: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    let isSelected: Bool
    let isDragging: Bool
    var isLinkHoverTarget = false
    var linkingRole: DependencyLinkingRole = .inactive
    let onEdit: () -> Void
    let onSelect: () -> Void

    private var metaLine: String {
        var parts: [String] = []
        if !context.jobTitle.isEmpty { parts.append(context.jobTitle) }
        if !context.projectTitle.isEmpty { parts.append(context.projectTitle) }
        return parts.isEmpty ? "Inbox" : parts.joined(separator: " · ")
    }

    private var pendingBlockers: [TaskContext] {
        store.pendingBlockers(for: context.task)
    }

    private var openFollowUps: [TaskContext] {
        store.openDependents(of: context.task.id)
    }

    private var isBlocked: Bool {
        !pendingBlockers.isEmpty
    }

    private var dependencySummary: String? {
        guard isBlocked else { return nil }
        let titles = pendingBlockers.map(\.task.title)
        if titles.count == 1 { return "After \(titles[0])" }
        if titles.count == 2 { return "After \(titles[0]) + 1 more" }
        return "After \(titles[0]) + \(titles.count - 1) more"
    }

    private var accentColor: Color {
        isBlocked ? TaskKanbanLayout.dependencyTint : context.jobColor
    }

    private var cardFillColor: Color {
        let done = context.task.status == .done
        if isSelected {
            return accentColor.opacity(done ? 0.10 : 0.14)
        }
        return accentColor.opacity(done ? 0.06 : 0.10)
    }

    private var cardBorderColor: Color {
        if linkingRole == .validTarget {
            return TaskKanbanLayout.dependencyTint.opacity(0.75)
        }
        if isLinkHoverTarget {
            return TaskKanbanLayout.dependencyTint.opacity(0.85)
        }
        let done = context.task.status == .done
        if isSelected {
            return accentColor.opacity(done ? 0.38 : 0.50)
        }
        return accentColor.opacity(done ? 0.28 : 0.40)
    }

    private var cardBorderWidth: CGFloat {
        if linkingRole == .validTarget || isLinkHoverTarget { return 2 }
        if isSelected { return 1.5 }
        return 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                Text(context.task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(context.task.status == .done ? TurboTheme.mutedInk : TurboTheme.ink)
                    .strikethrough(context.task.status == .done, color: TurboTheme.mutedInk.opacity(0.45))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let dependencySummary {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 8, weight: .bold))
                        Text(dependencySummary)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(TaskKanbanLayout.dependencyTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(TaskKanbanLayout.dependencyTint.opacity(0.12))
                    )
                }

                if !openFollowUps.isEmpty, context.task.status != .done {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(openFollowUps.count == 1 ? "Unlocks 1 task" : "Unlocks \(openFollowUps.count) tasks")
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(TurboTheme.mutedInk)
                }

                TaskSubtasksView(context: context, style: .kanban, maxVisible: 4)
                    .environmentObject(store)

                HStack(spacing: 6) {
                    if context.isOperationTask {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(context.jobColor)
                            .help("Operation: \(context.operationTitle)")
                            .accessibilityLabel("Operation: \(context.operationTitle)")
                    }
                    Text(metaLine)
                        .font(.system(size: 10))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(context.task.energy.shortTitle)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(context.task.energy.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(context.task.energy.accent.opacity(0.12)))
                }
            }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardFillColor)
                .shadow(color: TurboTheme.shadow.opacity(isDragging ? 0 : 0.35), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorderColor, lineWidth: cardBorderWidth)
        )
        .overlay {
            if isLinkHoverTarget {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TaskKanbanLayout.dependencyTint.opacity(0.08))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TaskKanbanLayout.dependencyTint)
                            .padding(6)
                    }
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2) {
            guard linkingRole == .inactive else { return }
            onEdit()
        }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEdit)
                .environmentObject(store)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(linkingRole == .inactive
            ? "Drag to move. Option-drag onto another card to link: that task starts after this one finishes."
            : linkingRole == .validTarget
                ? "Tap to set as prerequisite."
                : linkingRole == .source
                    ? "Choose another task that must finish before this one can start."
                    : "Cannot link to this task.")
    }

    private var accessibilityLabelText: String {
        var parts = [context.task.title, metaLine]
        if let dependencySummary { parts.append(dependencySummary) }
        if !openFollowUps.isEmpty {
            parts.append("Unlocks \(openFollowUps.count) tasks when done")
        }
        return parts.joined(separator: ". ")
    }
}

private struct KanbanDropLine: View {
    var body: some View {
        Rectangle()
            .fill(TurboTheme.accent)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

// MARK: - Drop delegates

private struct KanbanCardDropDelegate: DropDelegate {
    let targetTaskID: UUID
    let columnStatus: TaskStatus
    let drag: KanbanDragState
    let onDrop: (UUID) -> Void
    let onLink: (UUID) -> Void

    private var isLinking: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    func validateDrop(info: DropInfo) -> Bool {
        drag.draggedTaskID != nil && drag.draggedTaskID != targetTaskID
    }

    func dropEntered(info: DropInfo) {
        guard drag.draggedTaskID != nil, drag.draggedTaskID != targetTaskID else { return }
        drag.hoverHiddenBundle = nil
        if isLinking {
            drag.isLinkingDrop = true
            drag.hoverLinkTargetID = targetTaskID
            drag.hoverColumn = nil
            drag.hoverColumnEnd = false
            drag.hoverBeforeTaskID = nil
        } else {
            drag.isLinkingDrop = false
            drag.hoverLinkTargetID = nil
            drag.hoverColumn = columnStatus
            drag.hoverColumnEnd = false
            drag.hoverBeforeTaskID = targetTaskID
        }
    }

    func dropExited(info: DropInfo) {
        if drag.hoverBeforeTaskID == targetTaskID {
            drag.hoverBeforeTaskID = nil
        }
        if drag.hoverLinkTargetID == targetTaskID {
            drag.hoverLinkTargetID = nil
            drag.isLinkingDrop = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isLinking {
            drag.isLinkingDrop = true
            drag.hoverLinkTargetID = targetTaskID
            drag.hoverColumn = nil
            drag.hoverBeforeTaskID = nil
            drag.hoverColumnEnd = false
        } else if drag.isLinkingDrop {
            drag.isLinkingDrop = false
            drag.hoverLinkTargetID = nil
            drag.hoverColumn = columnStatus
            drag.hoverBeforeTaskID = targetTaskID
        }
        return DropProposal(operation: isLinking ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedTaskID, movingID != targetTaskID else {
            return false
        }
        if isLinking {
            onLink(movingID)
        } else {
            onDrop(movingID)
        }
        return true
    }
}

private struct KanbanColumnDropDelegate: DropDelegate {
    let columnStatus: TaskStatus
    let drag: KanbanDragState
    let onDropToColumn: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.draggedTaskID != nil }

    func dropEntered(info: DropInfo) {
        guard drag.draggedTaskID != nil else { return }
        drag.hoverHiddenBundle = nil
        drag.hoverColumn = columnStatus
        drag.hoverColumnEnd = false
        drag.hoverBeforeTaskID = nil
    }

    func dropExited(info: DropInfo) {
        if drag.hoverColumn == columnStatus, !drag.hoverColumnEnd {
            drag.hoverColumn = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedTaskID else { return false }
        onDropToColumn(movingID)
        return true
    }
}

private struct KanbanColumnEndDropDelegate: DropDelegate {
    let columnStatus: TaskStatus
    let drag: KanbanDragState
    let onDropToEnd: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.draggedTaskID != nil }

    func dropEntered(info: DropInfo) {
        guard drag.draggedTaskID != nil else { return }
        drag.hoverHiddenBundle = nil
        drag.hoverColumn = columnStatus
        drag.hoverColumnEnd = true
        drag.hoverBeforeTaskID = nil
    }

    func dropExited(info: DropInfo) {
        if drag.hoverColumn == columnStatus, drag.hoverColumnEnd {
            drag.hoverColumnEnd = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedTaskID else { return false }
        onDropToEnd(movingID)
        return true
    }
}

private struct KanbanHiddenBundleDropDelegate: DropDelegate {
    let columnStatus: TaskStatus
    let drag: KanbanDragState
    let onDrop: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.draggedTaskID != nil }

    func dropEntered(info: DropInfo) {
        guard drag.draggedTaskID != nil else { return }
        drag.hoverColumn = nil
        drag.hoverBeforeTaskID = nil
        drag.hoverColumnEnd = false
        drag.hoverHiddenBundle = columnStatus
    }

    func dropExited(info: DropInfo) {
        if drag.hoverHiddenBundle == columnStatus {
            drag.hoverHiddenBundle = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedTaskID else { return false }
        onDrop(movingID)
        return true
    }
}
