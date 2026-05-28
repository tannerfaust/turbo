//
//  TasksView.swift
//  Turbotask
//
//  Task registry: dense ledger of every task, distinct from Now’s card-first layout.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private func textInputHasFocusForTasks() -> Bool {
    guard let r = NSApp.keyWindow?.firstResponder else { return false }
    if r is NSTextView { return true }
    if r is NSTextField { return true }
    let desc = String(describing: type(of: r))
    return desc.contains("FieldEditor") || desc.contains("NSTextView")
}

// MARK: - Hub lens (presentation only; filtering is search + sort via store)

private enum TasksHubLens: String, CaseIterable, Identifiable {
    case all
    case byJob
    case byProject
    case byStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .byJob: "Jobs"
        case .byProject: "Projects"
        case .byStatus: "Status"
        }
    }
}

private struct TasksHubSectionPayload: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let accent: Color?
}

private enum TasksHubRowItem: Identifiable {
    case section(TasksHubSectionPayload)
    case task(TaskContext)

    var id: String {
        switch self {
        case .section(let p):
            p.id
        case .task(let c):
            "t:\(c.task.id.uuidString)"
        }
    }
}

private struct TasksProjectSectionKey: Hashable {
    var jobID: UUID?
    var projectID: UUID?
}

// MARK: - Main

struct TasksView: View {
    @EnvironmentObject private var store: TurboTaskStore
    @State private var lens: TasksHubLens = .all
    @State private var editingTask: TaskContext?
    @State private var tasksKeyMonitor: Any?
    @StateObject private var taskDrag = ReorderDragState()

    private var filteredTasks: [TaskContext] {
        store.filteredTaskContexts
    }

    private var rowItems: [TasksHubRowItem] {
        buildRowItems(lens: lens, tasks: filteredTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            registryHeader

            lensBar
                .padding(.top, 14)
                .padding(.bottom, 12)

            searchAndSortRow
                .padding(.bottom, 10)

            Group {
                if filteredTasks.isEmpty {
                    TurboEmptyState(
                        title: store.tasksQuery.search.isEmpty
                            ? "No tasks yet."
                            : "No tasks match “\(store.tasksQuery.search)”.",
                        actionTitle: "New task",
                        action: { store.openComposer(.task) }
                    )
                } else {
                    registryScroll
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TurboTheme.background)
        .onAppear {
            _Concurrency.Task { @MainActor in
                sanitizeTasksQueryForRegistry()
            }
            installTasksKeyMonitor()
        }
        .onDisappear {
            removeTasksKeyMonitor()
        }
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
                .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
    }

    // MARK: Header (registry — not the same silhouette as Now)

    private var registryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TASK REGISTRY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .tracking(1.1)
                Text("Every task in one place")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
            }
            Spacer(minLength: 8)
            Text("\(filteredTasks.count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(TurboTheme.ink.opacity(0.22))
                .contentTransition(.numericText())
            Button {
                store.openComposer(.task)
            } label: {
                Text("New")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(TurboTheme.ink)
            .controlSize(.regular)
            .trainingWheelsTooltip("New task in the composer · ⌘T")
        }
    }

    private var lensBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Group by")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TurboTheme.mutedInk)
                if let lensHint {
                    TurboInfoButton(title: "Grouping", message: lensHint)
                }
            }
            Picker("Group by", selection: $lens) {
                ForEach(TasksHubLens.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Group tasks by")
        }
    }

    private var lensHint: String? {
        switch lens {
        case .all:
            nil
        case .byJob:
            "One section per job. “Inbox & unassigned” is tasks with no job. Inside each job, tasks from every project and job-only tasks are listed together."
        case .byProject:
            "One section per project. “Job · tasks on job” means tasks not inside a project. Other sections use “Job · Project”."
        case .byStatus:
            "Groups tasks by their current status regardless of job or project."
        }
    }

    private var searchAndSortRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Search title, summary, job, project…", text: tasksSearchBinding)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TurboTheme.backgroundRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(TurboTheme.cardStroke.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
            .frame(maxWidth: .infinity)

            Toggle("Archived", isOn: tasksIncludeArchivedBinding)
                .toggleStyle(.checkbox)
                .help("Show archived tasks in this registry. Use the Archive page in the sidebar for a dedicated list.")

            Picker("Sort", selection: tasksSortBinding) {
                ForEach(TurboTaskStore.TaskSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 118)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var registryScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rowItems) { item in
                    switch item {
                    case .section(let payload):
                        TasksHubSectionHeader(payload: payload)
                    case .task(let context):
                        TasksRegistryRow(
                            context: context,
                            drag: taskDrag,
                            isSelected: isRowSelected(context),
                            isTypeaheadFocus: false,
                            onSelect: { select(context) },
                            onToggleNow: { store.toggleTaskNow(context) },
                            onEdit: { editingTask = context }
                        )
                        .environmentObject(store)
                        .overlay(alignment: .top) {
                            if taskDrag.draggedID != nil, !taskDrag.hoverIsEnd, taskDrag.hoverTargetID == context.task.id {
                                ReorderDropLine()
                            }
                        }
                        .onDrop(of: [.text], delegate: RowReorderDropDelegate(rowID: context.task.id, drag: taskDrag) { movingID in
                            reorderTaskInContainer(movingID, before: context)
                        })
                    }
                }

                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 18)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if taskDrag.draggedID != nil, taskDrag.hoverIsEnd { ReorderDropLine() }
                    }
                    .onDrop(of: [.text], delegate: EndReorderDropDelegate(drag: taskDrag) { movingID in
                        reorderTaskToEndInContainer(movingID)
                    })
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TurboTheme.cardStroke.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func reorderTaskInContainer(_ movingID: UUID, before target: TaskContext) {
        guard let moving = filteredTasks.first(where: { $0.task.id == movingID }) else { return }
        guard moving.jobID == target.jobID, moving.projectID == target.projectID else { return }
        guard let jobID = target.jobID else { return }
        if let projectID = target.projectID {
            store.reorderProjectTask(jobID, projectID: projectID, movingTaskID: movingID, before: target.task.id)
        } else {
            store.reorderJobTask(jobID, movingTaskID: movingID, before: target.task.id)
        }
    }

    private func reorderTaskToEndInContainer(_ movingID: UUID) {
        guard let moving = filteredTasks.first(where: { $0.task.id == movingID }) else { return }
        guard let jobID = moving.jobID else { return }
        if let projectID = moving.projectID {
            store.reorderProjectTaskToEnd(jobID, projectID: projectID, movingTaskID: movingID)
        } else {
            store.reorderJobTaskToEnd(jobID, movingTaskID: movingID)
        }
    }

    private func isRowSelected(_ context: TaskContext) -> Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private func select(_ context: TaskContext) {
        store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
    }

    private var tasksSearchBinding: Binding<String> {
        Binding(
            get: { store.tasksQuery.search },
            set: { newValue in
                guard store.tasksQuery.search != newValue else { return }
                _Concurrency.Task { @MainActor in
                    var query = store.tasksQuery
                    query.search = newValue
                    store.tasksQuery = query
                }
            }
        )
    }

    private var tasksSortBinding: Binding<TurboTaskStore.TaskSortOption> {
        Binding(
            get: { store.tasksQuery.sort },
            set: { newValue in
                guard store.tasksQuery.sort != newValue else { return }
                _Concurrency.Task { @MainActor in
                    var query = store.tasksQuery
                    query.sort = newValue
                    store.tasksQuery = query
                }
            }
        )
    }

    private var tasksIncludeArchivedBinding: Binding<Bool> {
        Binding(
            get: { store.tasksQuery.includeArchivedTasks },
            set: { newValue in
                guard store.tasksQuery.includeArchivedTasks != newValue else { return }
                _Concurrency.Task { @MainActor in
                    var query = store.tasksQuery
                    query.includeArchivedTasks = newValue
                    store.tasksQuery = query
                }
            }
        )
    }

    private func moveTaskSelection(_ delta: Int) {
        let tasks = filteredTasks
        guard !tasks.isEmpty else { return }

        if let selectedID = store.selectedTaskID,
           let currentIdx = tasks.firstIndex(where: { $0.task.id == selectedID }) {
            let nextIdx = min(max(0, currentIdx + delta), tasks.count - 1)
            let ctx = tasks[nextIdx]
            store.select(.task(jobID: ctx.jobID, projectID: ctx.projectID, taskID: ctx.task.id))
        } else if let first = tasks.first {
            store.select(.task(jobID: first.jobID, projectID: first.projectID, taskID: first.task.id))
        }
    }

    private func installTasksKeyMonitor() {
        guard tasksKeyMonitor == nil else { return }
        let st = store
        tasksKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Thread.isMainThread else { return event }
            guard st.selectedScreen == .tasks else { return event }
            guard st.composer == nil else { return event }

            if textInputHasFocusForTasks() { return event }

            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command) { return event }

            switch code {
            case 125, 124: // down, right
                MainActor.assumeIsolated {
                    moveTaskSelection(1)
                }
                return nil
            case 126, 123: // up, left
                MainActor.assumeIsolated {
                    moveTaskSelection(-1)
                }
                return nil
            case 36: // return - edit
                MainActor.assumeIsolated {
                    if let ctx = st.selectedTaskContext {
                        editingTask = ctx
                    }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeTasksKeyMonitor() {
        if let monitor = tasksKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        tasksKeyMonitor = nil
    }

    private func sanitizeTasksQueryForRegistry() {
        let sanitized = TurboTaskStore.TasksQuery(
            search: store.tasksQuery.search,
            jobID: nil,
            projectID: nil,
            status: nil,
            energy: nil,
            onlyNow: false,
            includeArchivedTasks: store.tasksQuery.includeArchivedTasks,
            sort: store.tasksQuery.sort
        )
        guard store.tasksQuery != sanitized else { return }
        store.tasksQuery = sanitized
    }

    private func buildRowItems(lens: TasksHubLens, tasks: [TaskContext]) -> [TasksHubRowItem] {
        guard !tasks.isEmpty else { return [] }
        switch lens {
        case .all:
            return tasks.map { .task($0) }

        case .byJob:
            var seen = Set<UUID?>()
            var order: [UUID?] = []
            for t in tasks {
                if seen.insert(t.jobID).inserted {
                    order.append(t.jobID)
                }
            }
            var rows: [TasksHubRowItem] = []
            for jid in order {
                let accent = tasks.first(where: { $0.jobID == jid })?.jobColor
                rows.append(.section(TasksHubSectionPayload(
                    id: "job:\(jid?.uuidString ?? "inbox")",
                    title: jobSectionTitle(jobID: jid, from: tasks),
                    subtitle: nil,
                    accent: accent
                )))
                for t in tasks where t.jobID == jid {
                    rows.append(.task(t))
                }
            }
            return rows

        case .byProject:
            var seen = Set<TasksProjectSectionKey>()
            var order: [TasksProjectSectionKey] = []
            for t in tasks {
                let k = TasksProjectSectionKey(jobID: t.jobID, projectID: t.projectID)
                if seen.insert(k).inserted {
                    order.append(k)
                }
            }
            var rows: [TasksHubRowItem] = []
            for k in order {
                let accent = tasks.first(where: { $0.jobID == k.jobID && $0.projectID == k.projectID })?.jobColor
                rows.append(.section(TasksHubSectionPayload(
                    id: "jp:\(k.jobID?.uuidString ?? "nil"):\(k.projectID?.uuidString ?? "nil")",
                    title: projectSectionTitle(key: k, from: tasks),
                    subtitle: nil,
                    accent: accent
                )))
                for t in tasks where t.jobID == k.jobID && t.projectID == k.projectID {
                    rows.append(.task(t))
                }
            }
            return rows

        case .byStatus:
            let statuses = TaskStatus.allCases
            var rows: [TasksHubRowItem] = []
            for st in statuses {
                let slice = tasks.filter { $0.task.status == st }
                guard !slice.isEmpty else { continue }
                rows.append(.section(TasksHubSectionPayload(
                    id: "status:\(st.rawValue)",
                    title: st.title.uppercased(),
                    subtitle: nil,
                    accent: nil
                )))
                for t in slice {
                    rows.append(.task(t))
                }
            }
            return rows
        }
    }

    private func jobSectionTitle(jobID: UUID?, from tasks: [TaskContext]) -> String {
        if let jobID,
           let ctx = tasks.first(where: { $0.jobID == jobID }) {
            return ctx.jobTitle.isEmpty ? "Job" : ctx.jobTitle
        }
        return "Inbox & unassigned"
    }

    private func projectSectionTitle(key: TasksProjectSectionKey, from tasks: [TaskContext]) -> String {
        guard let ctx = tasks.first(where: { $0.jobID == key.jobID && $0.projectID == key.projectID }) else {
            return "—"
        }
        if ctx.projectID == nil {
            return ctx.jobTitle.isEmpty ? "Job tasks" : "\(ctx.jobTitle) · tasks on job"
        }
        let p = ctx.projectTitle.isEmpty ? "Project" : ctx.projectTitle
        if ctx.jobTitle.isEmpty {
            return p
        }
        return "\(ctx.jobTitle) · \(p)"
    }
}

// MARK: - Section header (ledger strip)

private struct TasksHubSectionHeader: View {
    let payload: TasksHubSectionPayload

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let accent = payload.accent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(payload.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .tracking(0.55)
                if let sub = payload.subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TurboTheme.nestedCardFill.opacity(0.42))
    }
}

// MARK: - Dense registry row

private struct TasksRegistryRow: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    @ObservedObject var drag: ReorderDragState
    let isSelected: Bool
    let isTypeaheadFocus: Bool
    let onSelect: () -> Void
    let onToggleNow: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ReorderHandle()
                .opacity(isSelected ? 0.5 : 0.15)
                .onDrag {
                    drag.draggedID = context.task.id
                    return NSItemProvider(object: context.task.id.uuidString as NSString)
                } preview: {
                    Text(context.task.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 280, alignment: .leading)
                        .padding(6)
                        .background(TurboTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

            Rectangle()
                .fill(context.jobColor)
                .frame(width: 3)

            HStack(alignment: .center, spacing: 10) {
                TaskStatusRowIndicator(
                    status: context.task.status,
                    jobColor: context.jobColor,
                    diameter: 15
                )

                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.task.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TurboTheme.ink)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Text(metaLine)
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .trainingWheelsTooltip("Select task · use search ↑ ↓ + Return when filter is focused")

                Button(action: onToggleNow) {
                    Image(systemName: context.task.isScheduledNow ? "bolt.fill" : "bolt")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            context.task.isScheduledNow
                                ? context.jobColor
                                : TurboTheme.mutedInk.opacity(0.42)
                        )
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .trainingWheelsTooltip(context.task.isScheduledNow ? "Remove from Now" : "Add to Now")
                .accessibilityLabel(context.task.isScheduledNow ? "Remove from Now" : "Add to Now")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 7)
        }
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TurboTheme.divider.opacity(0.22))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if isTypeaheadFocus {
                Rectangle()
                    .fill(TurboTheme.ink.opacity(0.48))
                    .frame(width: 2)
                    .padding(.vertical, 5)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEdit)
                .environmentObject(store)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !context.jobTitle.isEmpty { parts.append(context.jobTitle) }
        if !context.projectTitle.isEmpty { parts.append(context.projectTitle) }
        let scope = parts.isEmpty ? "Inbox" : parts.joined(separator: " · ")
        let arch = context.task.isArchived ? "Archived · " : ""
        return "\(arch)\(scope) · \(context.task.energy.shortTitle)"
    }

    private var rowBackground: Color {
        if isSelected {
            return TurboTheme.accentSoft.opacity(0.52)
        }
        if isTypeaheadFocus {
            return TurboTheme.accentSoft.opacity(0.26)
        }
        return Color.clear
    }
}
