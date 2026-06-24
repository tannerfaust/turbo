//
//  JobsView.swift
//  Turbotask
//
//  Workbench layout: job directory (List) + single “work card” (scope chips + task table).
//  Visually distinct from Projects (rail + tiles + inspector).
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Browser scope

private enum JobsBrowserScope: Equatable {
    case directTasks
    case project(UUID)
}

private struct PendingProjectDelete: Equatable {
    let jobID: UUID
    let projectID: UUID
}

// MARK: - Root

struct JobsView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var search = ""
    @State private var browserJobID: UUID?
    @State private var scope: JobsBrowserScope = .directTasks
    @State private var pendingDeleteJob: Job?
    @State private var pendingDeleteProject: PendingProjectDelete?
    @State private var editingTask: TaskContext?
    @StateObject private var rowHighlight = TypeaheadRowHighlight()
    @StateObject private var jobsListCount = TypeaheadLiveCount()
    @State private var jobsKeyMonitor: Any?
    @StateObject private var jobDrag = ReorderDragState()
    @StateObject private var taskDrag = ReorderDragState()

    private var visibleJobs: [Job] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.jobs }
        return store.jobs.filter { job in
            store.jobSearchText(jobID: job.id).contains(query)
        }
    }

    private var selectedJob: Job? {
        guard let id = browserJobID else { return nil }
        return store.job(id: id)
    }

    private var displayedTasks: [TaskContext] {
        guard let job = selectedJob else { return [] }
        switch scope {
        case .directTasks:
            return store.jobLevelTaskContexts(jobID: job.id)
        case .project(let pid):
            return store.taskContexts(jobID: job.id, projectID: pid)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workbenchHeader

            if visibleJobs.isEmpty {
                emptyState
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 14) {
                        jobDirectoryColumn
                            .frame(width: min(280, max(232, geo.size.width * 0.26)))
                            .frame(height: geo.size.height)

                        jobWorkbenchCard
                            .frame(maxWidth: .infinity)
                            .frame(height: geo.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TurboTheme.background)
        .alert("Delete field?", isPresented: Binding(
            get: { pendingDeleteJob != nil },
            set: { if !$0 { pendingDeleteJob = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let j = pendingDeleteJob {
                    store.deleteJob(j.id)
                    if browserJobID == j.id {
                        browserJobID = store.jobs.first?.id
                        scope = .directTasks
                    }
                }
                pendingDeleteJob = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteJob = nil }
        } message: {
            Text("Removes the field, its projects, tasks, and related history.")
        }
        .alert("Delete project?", isPresented: Binding(
            get: { pendingDeleteProject != nil },
            set: { if !$0 { pendingDeleteProject = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let payload = pendingDeleteProject {
                    store.deleteProject(jobID: payload.jobID, projectID: payload.projectID)
                    if browserJobID == payload.jobID, case .project(let pid) = scope, pid == payload.projectID {
                        scope = .directTasks
                        store.select(.job(payload.jobID))
                    }
                }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
        } message: {
            Text("Removes the project, its tasks, and related history.")
        }
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
        }
        .onAppear {
            if browserJobID == nil {
                browserJobID = visibleJobs.first?.id ?? store.jobs.first?.id
            }
            installKeyMonitor()
            _Concurrency.Task { @MainActor in
                jobsListCount.value = visibleJobs.count
                if let id = browserJobID {
                    store.select(.job(id))
                }
            }
        }
        .onDisappear {
            TypeaheadListKeyboard.remove(jobsKeyMonitor)
            jobsKeyMonitor = nil
        }
        .onChange(of: store.selectedScreen) { _, screen in
            guard screen == .jobs else { return }
            _Concurrency.Task { @MainActor in
                jobsListCount.value = visibleJobs.count
            }
            installKeyMonitor()
        }
        .onChange(of: search) { _, _ in
            _Concurrency.Task { @MainActor in
                rowHighlight.reset()
                let c = visibleJobs.count
                jobsListCount.value = c
                rowHighlight.clamp(count: c)
            }
        }
        .onChange(of: visibleJobs.count) { _, c in
            _Concurrency.Task { @MainActor in
                jobsListCount.value = c
                rowHighlight.clamp(count: c)
            }
            if let jid = browserJobID, !visibleJobs.contains(where: { $0.id == jid }) {
                browserJobID = visibleJobs.first?.id
                scope = .directTasks
            }
        }
        .onChange(of: browserJobID) { _, newID in
            scope = .directTasks
            if let id = newID {
                _Concurrency.Task { @MainActor in
                    store.select(.job(id))
                }
            }
        }
        .onChange(of: store.jobs.count) { _, _ in
            _Concurrency.Task { @MainActor in
                jobsListCount.value = visibleJobs.count
                rowHighlight.clamp(count: visibleJobs.count)
            }
        }
        .onChange(of: store.jobs) { _, _ in
            if case .project(let pid) = scope,
               let jid = browserJobID,
               let job = store.jobs.first(where: { $0.id == jid }),
               !job.projects.contains(where: { $0.id == pid }) {
                scope = .directTasks
                _Concurrency.Task { @MainActor in
                    store.select(.job(jid))
                }
            }
        }
    }

    // MARK: Header (distinct from Projects “portfolio” strip)

    private var workbenchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FIELD WORKBENCH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .tracking(1.15)
                    Text("Pick a field, choose a scope, work the list")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                }
                Spacer(minLength: 12)
                Button("New field") {
                    store.openComposer(.job)
                }
                .buttonStyle(.borderedProminent)
                .tint(TurboTheme.ink)
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .trainingWheelsTooltip("New field · ⌘⇧J")
            }

            HStack(spacing: 10) {
                IdentifiedTextField(
                    identifier: TypeaheadFieldID.jobsSearch,
                    text: $search,
                    placeholder: "Filter fields…"
                )
                .frame(height: 26)

                Text("\(visibleJobs.count) fields")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(TurboTheme.mutedInk)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TurboTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TurboTheme.cardStroke, lineWidth: 1)
                    )
            )

            TrainingWheelsHint(text: "Search focused: ↑ ↓ and Return selects a field in the directory.")
                .padding(.top, 2)
        }
        .padding(.bottom, 14)
    }

    // MARK: Column — Job directory (List for reliable selection)

    private var jobDirectoryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Directory")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TurboTheme.mutedInk)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleJobs.enumerated()), id: \.element.id) { index, job in
                            jobDirectoryRow(job: job, index: index)
                                .id(job.id)
                                .overlay(alignment: .top) {
                                    if jobDrag.draggedID != nil, !jobDrag.hoverIsEnd, jobDrag.hoverTargetID == job.id {
                                        ReorderDropLine()
                                    }
                                }
                                .onDrop(of: [.text], delegate: RowReorderDropDelegate(rowID: job.id, drag: jobDrag) { movingID in
                                    store.reorderJob(movingID, before: job.id)
                                })
                                .padding(.horizontal, 8)
                                .background(directoryRowBackground(index: index, jobID: job.id))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    browserJobID = job.id
                                }
                                .contextMenu {
                                    Button("Delete field…") {
                                        pendingDeleteJob = job
                                    }
                                }
                        }

                        Color.clear
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if jobDrag.draggedID != nil, jobDrag.hoverIsEnd { ReorderDropLine() }
                            }
                            .onDrop(of: [.text], delegate: EndReorderDropDelegate(drag: jobDrag) { movingID in
                                store.reorderJobToEnd(movingID)
                            })
                    }
                }
                .onReceive(rowHighlight.$index) { newValue in
                    guard visibleJobs.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(visibleJobs[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TurboTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TurboTheme.cardStroke, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func directoryRowBackground(index: Int, jobID: UUID) -> some View {
        let typeahead = index == rowHighlight.index
            && TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.jobsSearch)
        let picked = browserJobID == jobID
        return Group {
            if picked {
                TurboTheme.accentSoft.opacity(0.65)
            } else if typeahead {
                TurboTheme.rowHover
            } else {
                Color.clear
            }
        }
    }

    private func jobDirectoryRow(job: Job, index: Int) -> some View {
        HStack(spacing: 6) {
            ReorderHandle()
                .opacity(browserJobID == job.id ? 0.5 : 0.2)
                .onDrag {
                    jobDrag.draggedID = job.id
                    return NSItemProvider(object: job.id.uuidString as NSString)
                } preview: {
                    Text(job.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                        .padding(6)
                        .background(TurboTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(job.palette.color)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                if browserJobID == job.id {
                    TextField(
                        "Field name",
                        text: Binding(
                            get: { job.title },
                            set: { value in
                                store.updateJob(jobID: job.id) { $0.title = value }
                            }
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(2)
                } else {
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text("\(job.projects.count) projects · \(openWorkCount(job)) open")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func openWorkCount(_ job: Job) -> Int {
        store.jobOpenWorkCount(jobID: job.id)
    }

    // MARK: Work card — scope chips + tasks (not a second “rail”)

    private var jobWorkbenchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job = selectedJob {
                workbenchJobHeader(job: job)

                Rectangle()
                    .fill(TurboTheme.divider.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 12)

                Text("Where to work")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .padding(.bottom, 8)

                scopeChipStrip(job: job)

                Rectangle()
                    .fill(TurboTheme.divider.opacity(0.45))
                    .frame(height: 1)
                    .padding(.vertical, 12)

                workbenchTasksSection
            } else {
                Text("Choose a field in the directory.")
                    .font(.body)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TurboTheme.backgroundRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TurboTheme.cardStroke, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func workbenchJobHeader(job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                FieldAppearanceEditor(jobID: job.id, showsSummary: true)
                    .environmentObject(store)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("New project") {
                        store.select(.job(job.id))
                        store.openNewProject(preferredJobID: job.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(job.palette.color)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .trainingWheelsTooltip("New project on this field · ⌘⇧P")

                    Button("New task") {
                        store.select(.job(job.id))
                        store.openComposer(.task)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TurboTheme.ink)
                    .controlSize(.regular)
                    .keyboardShortcut("t", modifiers: .command)
                    .trainingWheelsTooltip("New task · ⌘T")
                }
            }
        }
    }

    private func scopeChipStrip(job: Job) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                scopeChip(
                    title: "Direct tasks",
                    subtitle: "On field only",
                    count: job.jobTasks.filter { !$0.isArchived && $0.status != .done }.count,
                    selected: scope == .directTasks
                ) {
                    scope = .directTasks
                    store.select(.job(job.id))
                }

                ForEach(job.projects.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })) { project in
                    let open = project.tasks.filter { !$0.isArchived && $0.status != .done }.count
                    scopeChip(
                        title: project.displayTitle,
                        subtitle: project.outcome.isEmpty ? "Project" : String(project.outcome.prefix(36)) + (project.outcome.count > 36 ? "…" : ""),
                        count: open,
                        selected: scope == .project(project.id)
                    ) {
                        scope = .project(project.id)
                        store.select(.project(jobID: job.id, projectID: project.id))
                    }
                    .contextMenu {
                        Button("Delete project…", role: .destructive) {
                            pendingDeleteProject = PendingProjectDelete(jobID: job.id, projectID: project.id)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func scopeChip(
        title: String,
        subtitle: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(1)
                    Text("\(count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(selected ? TurboTheme.ink : TurboTheme.mutedInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(TurboTheme.nestedCardFill.opacity(selected ? 0.95 : 0.6)))
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? TurboTheme.accentSoft.opacity(0.55) : TurboTheme.nestedCardFill.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? TurboTheme.ink.opacity(0.22) : TurboTheme.cardStroke.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var workbenchTasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(scopeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                Spacer()
                Button("Add task") {
                    addTaskForCurrentScope()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .trainingWheelsTooltip("Opens task composer for this scope · ⌘T also works if this field/project is selected")
            }
            .padding(.bottom, 10)

            if displayedTasks.isEmpty {
                Text(scope == .directTasks ? "No direct tasks yet." : "No tasks in this project yet.")
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        workbenchTaskHeaderRow
                        ForEach(displayedTasks) { ctx in
                            JobsWorkbenchTaskRow(context: ctx, drag: taskDrag, onEdit: { editingTask = ctx })
                                .environmentObject(store)
                                .overlay(alignment: .top) {
                                    if taskDrag.draggedID != nil, !taskDrag.hoverIsEnd, taskDrag.hoverTargetID == ctx.task.id {
                                        ReorderDropLine()
                                    }
                                }
                                .onDrop(of: [.text], delegate: RowReorderDropDelegate(rowID: ctx.task.id, drag: taskDrag) { movingID in
                                    reorderWorkbenchTask(movingID, before: ctx.task.id)
                                })
                            if ctx.task.id != displayedTasks.last?.task.id {
                                Rectangle()
                                    .fill(TurboTheme.divider.opacity(0.35))
                                    .frame(height: 1)
                            }
                        }

                        Color.clear
                            .frame(maxWidth: .infinity).frame(height: 18)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if taskDrag.draggedID != nil, taskDrag.hoverIsEnd { ReorderDropLine() }
                            }
                            .onDrop(of: [.text], delegate: EndReorderDropDelegate(drag: taskDrag) { movingID in
                                reorderWorkbenchTaskToEnd(movingID)
                            })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reorderWorkbenchTask(_ movingID: UUID, before targetID: UUID) {
        guard let jobID = browserJobID else { return }
        switch scope {
        case .directTasks:
            store.reorderJobTask(jobID, movingTaskID: movingID, before: targetID)
        case .project(let pid):
            store.reorderProjectTask(jobID, projectID: pid, movingTaskID: movingID, before: targetID)
        }
    }

    private func reorderWorkbenchTaskToEnd(_ movingID: UUID) {
        guard let jobID = browserJobID else { return }
        switch scope {
        case .directTasks:
            store.reorderJobTaskToEnd(jobID, movingTaskID: movingID)
        case .project(let pid):
            store.reorderProjectTaskToEnd(jobID, projectID: pid, movingTaskID: movingID)
        }
    }

    private var workbenchTaskHeaderRow: some View {
        HStack(spacing: 8) {
            Text("STATUS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 52, alignment: .leading)
            Text("TASK")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TurboTheme.mutedInk)
            Spacer()
            Text("NOW")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 36, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TurboTheme.nestedCardFill.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.bottom, 6)
    }

    private var scopeTitle: String {
        guard let job = selectedJob else { return "Tasks" }
        switch scope {
        case .directTasks:
            return "Direct tasks · \(job.title)"
        case .project(let pid):
            if let p = job.projects.first(where: { $0.id == pid }) {
                return p.displayTitle
            }
            return "Tasks"
        }
    }

    private var emptyState: some View {
        TurboEmptyState(
            title: search.isEmpty ? "No fields yet." : "No fields match your filter.",
            actionTitle: "New field",
            action: { store.openComposer(.job) }
        )
    }

    private func sortTasks(lhs: TaskContext, rhs: TaskContext) -> Bool {
        if lhs.task.status == .active && rhs.task.status != .active { return true }
        if lhs.task.status != .active && rhs.task.status == .active { return false }
        if lhs.task.isScheduledNow != rhs.task.isScheduledNow { return lhs.task.isScheduledNow && !rhs.task.isScheduledNow }
        if lhs.task.priority != rhs.task.priority { return lhs.task.priority > rhs.task.priority }
        return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
    }

    private func addTaskForCurrentScope() {
        guard let job = selectedJob else { return }
        switch scope {
        case .directTasks:
            store.select(.job(job.id))
            store.openComposer(.task)
        case .project(let pid):
            store.select(.project(jobID: job.id, projectID: pid))
            store.openComposer(.task)
        }
    }

    private func installKeyMonitor() {
        TypeaheadListKeyboard.remove(jobsKeyMonitor)
        jobsKeyMonitor = TypeaheadListKeyboard.install(
            store: store,
            isSearchFocused: {
                guard store.selectedScreen == .jobs else { return false }
                return TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.jobsSearch)
            },
            itemCount: { jobsListCount.value },
            highlight: rowHighlight,
            onActivate: { idx in
                guard visibleJobs.indices.contains(idx) else { return }
                let job = visibleJobs[idx]
                browserJobID = job.id
                store.select(.job(job.id))
            }
        )
    }
}

// MARK: - Task row (table-style)

private struct JobsWorkbenchTaskRow: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    @ObservedObject var drag: ReorderDragState
    let onEdit: () -> Void

    private var isSelected: Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            ReorderHandle()
                .opacity(isSelected ? 0.5 : 0.2)
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

            TaskStatusRowIndicator(
                status: context.task.status,
                jobColor: context.jobColor,
                diameter: 14
            )
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    store.selectTask(context)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.task.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(TurboTheme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if !context.task.nextStep.isEmpty {
                            Text(context.task.nextStep)
                                .font(.caption2)
                                .foregroundStyle(TurboTheme.mutedInk)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .trainingWheelsTooltip("Select for ⌘↩ ⌘P ⌘D ⌘⇧U")

                TaskSubtasksView(context: context, style: .list)
                    .environmentObject(store)
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.toggleTaskNow(context)
            } label: {
                Image(systemName: context.task.isScheduledNow ? "bolt.fill" : "bolt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        context.task.isScheduledNow ? context.jobColor : TurboTheme.mutedInk.opacity(0.45)
                    )
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trainingWheelsTooltip(context.task.isScheduledNow ? "Remove from Now" : "Add to Now")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isSelected ? TurboTheme.rowSelected.opacity(0.85) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEdit)
                .environmentObject(store)
        }
    }
}
