//
//  ProjectsView.swift
//  Turbotask
//
//  Portfolio layout: job rail · project tiles · inspector (distinct from Now + Tasks).
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Date sheet payload

private struct TaskDateEditPayload: Identifiable {
    let id: UUID
    let jobID: UUID?
    let projectID: UUID?

    init(context: TaskContext) {
        id = context.task.id
        jobID = context.jobID
        projectID = context.projectID
    }
}

// MARK: - Root

struct ProjectsView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var focusedJobID: UUID?
    @State private var editingTask: TaskContext?
    @State private var dateEditPayload: TaskDateEditPayload?
    @State private var pendingDeleteProject: ProjectContext?
    @StateObject private var projectGridHighlight = TypeaheadRowHighlight()
    @State private var projectsKeyboardToken = ProjectsKeyboardMonitorToken()

    private var projectSearchIsEmpty: Bool {
        store.projectsQuery.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var projectsInJob: [ProjectContext] {
        guard let jid = focusedJobID else { return [] }
        let filtered = store.projectContexts(jobID: jid).filter { context in
            let query = store.projectsQuery.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return context.project.title.lowercased().contains(query)
                || context.project.outcome.lowercased().contains(query)
                || context.jobTitle.lowercased().contains(query)
        }
        switch store.projectsQuery.sort {
        case .manual:
            return filtered
        default:
            return filtered.sorted(by: projectSort)
        }
    }

    private var selectedContext: ProjectContext? {
        guard let pid = store.selectedProjectID,
              let match = projectsInJob.first(where: { $0.project.id == pid }) else {
            return projectsInJob.first
        }
        return match
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            portfolioHeader

            HStack(alignment: .top, spacing: 0) {
                jobsRail
                    .frame(width: 216)

                Rectangle()
                    .fill(TurboTheme.cardStroke.opacity(0.35))
                    .frame(width: 1)

                projectCanvas
                    .frame(minWidth: 280, maxWidth: .infinity)

                Rectangle()
                    .fill(TurboTheme.cardStroke.opacity(0.35))
                    .frame(width: 1)

                inspectorColumn
                    .frame(width: 308)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TurboTheme.background)
        .alert("Delete project?", isPresented: Binding(
            get: { pendingDeleteProject != nil },
            set: { if !$0 { pendingDeleteProject = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let ctx = pendingDeleteProject {
                    store.deleteProject(jobID: ctx.jobID, projectID: ctx.project.id)
                }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
        } message: {
            Text("Removes this project and all tasks in it, including related history.")
        }
        .onAppear {
            if focusedJobID == nil {
                focusedJobID = store.jobs.first?.id
            }
            reinstallProjectsKeyboardMonitor()
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
                syncSelectionToJob()
            }
        }
        .onDisappear {
            TypeaheadListKeyboard.remove(projectsKeyboardToken.monitor)
            projectsKeyboardToken.monitor = nil
        }
        .onChange(of: focusedJobID) { _, _ in
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
                syncSelectionToJob()
            }
        }
        .onChange(of: store.jobs.count) { _, _ in
            if let jid = focusedJobID, !store.jobs.contains(where: { $0.id == jid }) {
                focusedJobID = store.jobs.first?.id
            }
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
                syncSelectionToJob()
            }
        }
        .onChange(of: store.jobs) { _, _ in
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
                syncSelectionToJob()
            }
        }
        .onChange(of: store.projectsQuery.search) { _, _ in
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
            }
        }
        .onChange(of: store.projectsQuery.sort) { _, _ in
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
            }
        }
        .onChange(of: store.selectedScreen) { _, screen in
            guard screen == .projects else { return }
            _Concurrency.Task { @MainActor in
                syncProjectGridKeyboardState()
            }
            reinstallProjectsKeyboardMonitor()
        }
        .sheet(item: $dateEditPayload) { payload in
            TaskPlanDatesSheet(payload: payload)
                .environmentObject(store)
        }
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
                .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
    }

    // MARK: Header

    private var portfolioHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PORTFOLIO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .tracking(1.05)
                Text("Projects by job")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                IdentifiedTextField(
                    identifier: TypeaheadFieldID.projectsRailSearch,
                    text: Binding(
                        get: { store.projectsQuery.search },
                        set: { val in _Concurrency.Task { @MainActor in store.projectsQuery.search = val } }
                    ),
                    placeholder: "Filter projects…"
                )
                .frame(height: 24)
                .frame(maxWidth: 280)

                Picker("Sort", selection: Binding(
                    get: { store.projectsQuery.sort },
                    set: { val in _Concurrency.Task { @MainActor in store.projectsQuery.sort = val } }
                )) {
                    ForEach(TurboTaskStore.ProjectSortOption.allCases) { opt in
                        Text(opt.title).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 118)

                if let jid = focusedJobID {
                    Button("New project") {
                        store.openNewProject(preferredJobID: jid)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TurboTheme.ink)
                    .trainingWheelsTooltip("New project on the selected job · ⌘⇧P")
                }
            }

        }
        .padding(.bottom, 16)
    }

    // MARK: Jobs rail

    private var jobsRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Jobs")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            List {
                ForEach(store.jobs) { job in
                    PortfolioJobRow(
                        job: job,
                        projectCount: store.projectCount(jobID: job.id),
                        isSelected: focusedJobID == job.id
                    ) {
                        focusedJobID = job.id
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    store.moveJobs(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .background(TurboTheme.nestedCardFill.opacity(0.35))
    }

    // MARK: Project tiles

    private var projectCanvas: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.jobs.isEmpty {
                TurboEmptyState(
                    title: "Create a job first.",
                    actionTitle: "New job",
                    action: { store.openComposer(.job) }
                )
            } else if focusedJobID == nil {
                contentPlaceholder("Pick a job on the left.")
            } else if projectsInJob.isEmpty {
                contentPlaceholder("No projects in this job yet.")
            } else {
                ScrollViewReader { proxy in
                    Group {
                        if store.projectsQuery.sort == .manual {
                            List {
                                ForEach(Array(projectsInJob.enumerated()), id: \.element.project.id) { index, ctx in
                                    PortfolioProjectTile(
                                        context: ctx,
                                        isSelected: store.selectedProjectID == ctx.project.id,
                                        isTypeaheadFocus: index == projectGridHighlight.index
                                            && TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.projectsRailSearch),
                                        onSelect: {
                                            store.select(.project(jobID: ctx.jobID, projectID: ctx.project.id))
                                            _Concurrency.Task { @MainActor in
                                                projectGridHighlight.index = index
                                            }
                                        },
                                        onRequestDelete: { pendingDeleteProject = ctx }
                                    )
                                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .id(ctx.project.id)
                                }
                                .onMove { source, destination in
                                    guard projectSearchIsEmpty, let jid = focusedJobID else { return }
                                    store.moveProjects(jobID: jid, fromOffsets: source, toOffset: destination)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 12, alignment: .top)
                                    ],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    ForEach(Array(projectsInJob.enumerated()), id: \.element.project.id) { index, ctx in
                                        PortfolioProjectTile(
                                            context: ctx,
                                            isSelected: store.selectedProjectID == ctx.project.id,
                                            isTypeaheadFocus: index == projectGridHighlight.index
                                                && TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.projectsRailSearch),
                                            onSelect: {
                                                store.select(.project(jobID: ctx.jobID, projectID: ctx.project.id))
                                                _Concurrency.Task { @MainActor in
                                                    projectGridHighlight.index = index
                                                }
                                            },
                                            onRequestDelete: { pendingDeleteProject = ctx }
                                        )
                                        .id(ctx.project.id)
                                    }
                                }
                                .padding(12)
                            }
                        }
                    }
                    .onReceive(projectGridHighlight.$index) { idx in
                        guard projectsInJob.indices.contains(idx) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(projectsInJob[idx].project.id, anchor: .center)
                        }
                    }
                    .onChange(of: store.selectedProjectID) { _, newID in
                        guard let pid = newID,
                              let idx = projectsInJob.firstIndex(where: { $0.project.id == pid }) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(pid, anchor: .center)
                        }
                        _Concurrency.Task { @MainActor in
                            projectGridHighlight.index = idx
                        }
                    }
                }
            }
        }
        .background(TurboTheme.nestedCardFill.opacity(0.2))
    }

    private func contentPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(TurboTheme.mutedInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
    }

    // MARK: Inspector

    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Detail")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let ctx = selectedContext {
                PortfolioInspector(
                    context: ctx,
                    onEditDates: { t in dateEditPayload = TaskDateEditPayload(context: t) },
                    onEditTask: { editingTask = $0 },
                    onRequestDeleteProject: { pendingDeleteProject = ctx }
                )
                .environmentObject(store)
            } else {
                Text("Select a project tile.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(16)
            }
        }
        .padding(.vertical, 8)
        .background(TurboTheme.nestedCardFill.opacity(0.35))
    }

    private func syncSelectionToJob() {
        guard let jid = focusedJobID else { return }
        let list = projectsInJob.filter { $0.jobID == jid }
        guard let first = list.first else {
            return
        }
        if let sid = store.selectedProjectID,
           list.contains(where: { $0.project.id == sid }) {
            return
        }
        store.select(.project(jobID: first.jobID, projectID: first.project.id))
    }

    private func syncProjectGridKeyboardState() {
        let c = projectsInJob.count
        projectGridHighlight.clamp(count: c)
        alignProjectGridHighlightWithSelection()
    }

    private func alignProjectGridHighlightWithSelection() {
        guard let pid = store.selectedProjectID,
              let idx = projectsInJob.firstIndex(where: { $0.project.id == pid }) else {
            projectGridHighlight.index = 0
            return
        }
        projectGridHighlight.index = idx
    }

    private func reinstallProjectsKeyboardMonitor() {
        TypeaheadListKeyboard.remove(projectsKeyboardToken.monitor)
        let jobBinding = $focusedJobID
        let highlight = projectGridHighlight
        let st = store
        projectsKeyboardToken.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Thread.isMainThread else { return event }
            return ProjectsViewKeyRouting.handle(
                event: event,
                store: st,
                focusedJobID: jobBinding,
                highlight: highlight
            )
        }
    }

    private func projectSort(lhs: ProjectContext, rhs: ProjectContext) -> Bool {
        switch store.projectsQuery.sort {
        case .openTasks:
            if lhs.openTaskCount != rhs.openTaskCount {
                return lhs.openTaskCount > rhs.openTaskCount
            }
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .completion:
            if lhs.completionPercent != rhs.completionPercent {
                return lhs.completionPercent < rhs.completionPercent
            }
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .title:
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .manual:
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        }
    }
}

// MARK: - Keyboard (portfolio)

private final class ProjectsKeyboardMonitorToken {
    var monitor: Any?
    deinit {
        TypeaheadListKeyboard.remove(monitor)
    }
}

private enum ProjectsViewKeyRouting {
    static func handle(
        event: NSEvent,
        store: TurboTaskStore,
        focusedJobID: Binding<UUID?>,
        highlight: TypeaheadRowHighlight
    ) -> NSEvent? {
        guard store.selectedScreen == .projects else { return event }
        guard store.typeaheadListNavigationEnabled else { return event }

        let code = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), code != 36 {
            return event
        }

        let projects = projectList(store: store, focusedJobID: focusedJobID.wrappedValue)
        let count = projects.count

        let filterFocused = TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.projectsRailSearch)

        if filterFocused {
            guard count > 0 else { return event }
            switch code {
            case 125:
                highlight.move(by: 1, count: count)
                return nil
            case 126:
                highlight.move(by: -1, count: count)
                return nil
            case 36:
                if flags.contains(.command) { return event }
                let idx = highlight.index
                guard projects.indices.contains(idx) else { return event }
                let ctx = projects[idx]
                store.select(.project(jobID: ctx.jobID, projectID: ctx.project.id))
                return nil
            default:
                return event
            }
        }

        if projectsPortfolioTextInputHasFocus() {
            return event
        }

        let jobs = store.jobs
        guard !jobs.isEmpty else { return event }

        switch code {
        case 123:
            cycleJob(in: jobs, delta: -1, focusedJobID: focusedJobID)
            return nil
        case 124:
            cycleJob(in: jobs, delta: 1, focusedJobID: focusedJobID)
            return nil
        case 125:
            guard count > 0 else { return event }
            moveProjectSelection(in: projects, delta: 1, store: store, highlight: highlight)
            return nil
        case 126:
            guard count > 0 else { return event }
            moveProjectSelection(in: projects, delta: -1, store: store, highlight: highlight)
            return nil
        default:
            return event
        }
    }

    private static func projectList(store: TurboTaskStore, focusedJobID: UUID?) -> [ProjectContext] {
        guard let jid = focusedJobID else { return [] }
        let query = store.projectsQuery.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = store.projectContexts(jobID: jid).filter { context in
            guard !query.isEmpty else { return true }
            return context.project.title.lowercased().contains(query)
                || context.project.outcome.lowercased().contains(query)
                || context.jobTitle.lowercased().contains(query)
        }
        switch store.projectsQuery.sort {
        case .manual:
            return filtered
        default:
            return filtered.sorted { lhs, rhs in projectSort(lhs, rhs, store) }
        }
    }

    private static func projectSort(_ lhs: ProjectContext, _ rhs: ProjectContext, _ store: TurboTaskStore) -> Bool {
        switch store.projectsQuery.sort {
        case .openTasks:
            if lhs.openTaskCount != rhs.openTaskCount { return lhs.openTaskCount > rhs.openTaskCount }
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .completion:
            if lhs.completionPercent != rhs.completionPercent { return lhs.completionPercent < rhs.completionPercent }
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .title:
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        case .manual:
            return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
        }
    }

    private static func cycleJob(in jobs: [Job], delta: Int, focusedJobID: Binding<UUID?>) {
        guard let jid = focusedJobID.wrappedValue,
              let idx = jobs.firstIndex(where: { $0.id == jid }) else {
            focusedJobID.wrappedValue = jobs.first?.id
            return
        }
        let n = jobs.count
        let next = ((idx + delta) % n + n) % n
        focusedJobID.wrappedValue = jobs[next].id
    }

    private static func moveProjectSelection(
        in projects: [ProjectContext],
        delta: Int,
        store: TurboTaskStore,
        highlight: TypeaheadRowHighlight
    ) {
        guard let pid = store.selectedProjectID,
              let idx = projects.firstIndex(where: { $0.project.id == pid }) else {
            if let first = projects.first {
                store.select(.project(jobID: first.jobID, projectID: first.project.id))
                highlight.index = 0
            }
            return
        }
        let next = min(max(0, idx + delta), projects.count - 1)
        let ctx = projects[next]
        store.select(.project(jobID: ctx.jobID, projectID: ctx.project.id))
        highlight.index = next
    }

    private static func projectsPortfolioTextInputHasFocus() -> Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        if r is NSTextView { return true }
        if r is NSTextField { return true }
        let desc = String(describing: type(of: r))
        if desc.contains("FieldEditor") { return true }
        if desc.contains("NSTextView") { return true }
        return false
    }
}

// MARK: - Job row

private struct PortfolioJobRow: View {
    let job: Job
    let projectCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(job.palette.color)
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(projectCount) projects")
                        .font(.caption2)
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? TurboTheme.accentSoft.opacity(0.55) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? job.palette.color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project tile

private struct PortfolioProjectTile: View {
    let context: ProjectContext
    let isSelected: Bool
    var isTypeaheadFocus: Bool = false
    let onSelect: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(context.project.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int((context.completionPercent * 100).rounded()))%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(TurboTheme.mutedInk)
                }

                Text(context.project.outcome)
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                TurboProgressBar(value: context.completionPercent, tint: context.jobColor)
                    .frame(height: 3)

                HStack(spacing: 8) {
                    Text("\(context.openTaskCount) open")
                    Text("·")
                    Text("\(context.doneTaskCount) done")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TurboTheme.cardFill.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                strokeColor,
                                lineWidth: isSelected || isTypeaheadFocus ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete project…", role: .destructive) {
                onRequestDelete()
            }
        }
    }

    private var strokeColor: Color {
        if isSelected {
            return context.jobColor.opacity(0.5)
        }
        if isTypeaheadFocus {
            return TurboTheme.ink.opacity(0.35)
        }
        return TurboTheme.cardStroke.opacity(0.5)
    }
}

// MARK: - Inspector

private struct PortfolioInspector: View {
    @EnvironmentObject private var store: TurboTaskStore
    @StateObject private var drag = ReorderDragState()

    let context: ProjectContext
    let onEditDates: (TaskContext) -> Void
    let onEditTask: (TaskContext) -> Void
    let onRequestDeleteProject: () -> Void

    private var tasks: [TaskContext] {
        store.taskContexts(jobID: context.jobID, projectID: context.project.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    EmojiPickButton(
                        emoji: Binding(
                            get: { context.project.iconEmoji },
                            set: { newEmoji in
                                _Concurrency.Task { @MainActor in
                                    store.updateProject(jobID: context.jobID, projectID: context.project.id) {
                                        $0.iconEmoji = newEmoji
                                    }
                                }
                            }
                        )
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            "Title",
                            text: Binding(
                                get: { context.project.title },
                                set: { t in
                                    _Concurrency.Task { @MainActor in
                                        store.updateProject(jobID: context.jobID, projectID: context.project.id) {
                                            $0.title = t
                                        }
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)

                        TextField(
                            "Outcome",
                            text: Binding(
                                get: { context.project.outcome },
                                set: { o in
                                    _Concurrency.Task { @MainActor in
                                        store.updateProject(jobID: context.jobID, projectID: context.project.id) {
                                            $0.outcome = o
                                        }
                                    }
                                }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(3...6)
                    }
                }

                HStack {
                    Text("Tasks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TurboTheme.mutedInk)
                    Spacer()
                    Button("Add") {
                        store.select(.project(jobID: context.jobID, projectID: context.project.id))
                        store.openComposer(.task)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tasks) { tctx in
                        PortfolioTaskRow(
                            context: tctx,
                            drag: drag,
                            onSelect: { store.selectTask(tctx) },
                            onToggleNow: { store.toggleTaskNow(tctx) },
                            onEditDates: { onEditDates(tctx) },
                            onEditTask: { onEditTask(tctx) }
                        )
                        .environmentObject(store)
                        .overlay(alignment: .top) {
                            if drag.draggedID != nil, !drag.hoverIsEnd, drag.hoverTargetID == tctx.task.id {
                                ReorderDropLine()
                            }
                        }
                        .onDrop(of: [.text], delegate: RowReorderDropDelegate(rowID: tctx.task.id, drag: drag) { movingID in
                            store.reorderProjectTask(context.jobID, projectID: context.project.id, movingTaskID: movingID, before: tctx.task.id)
                        })
                        if tctx.task.id != tasks.last?.task.id {
                            Divider().opacity(0.35)
                        }
                    }

                    Color.clear
                        .frame(maxWidth: .infinity).frame(height: 14)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if drag.draggedID != nil, drag.hoverIsEnd { ReorderDropLine() }
                        }
                        .onDrop(of: [.text], delegate: EndReorderDropDelegate(drag: drag) { movingID in
                            store.reorderProjectTaskToEnd(context.jobID, projectID: context.project.id, movingTaskID: movingID)
                        })
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Delete project…", role: .destructive) {
                    onRequestDeleteProject()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .padding(12)
        }
    }
}

// MARK: - Task row (inspector)

private struct PortfolioTaskRow: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    @ObservedObject var drag: ReorderDragState
    let onSelect: () -> Void
    let onToggleNow: () -> Void
    let onEditDates: () -> Void
    let onEditTask: () -> Void

    private var isSelected: Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private var overdue: Bool {
        context.task.isEndDateOverdue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
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
                        .frame(maxWidth: 200, alignment: .leading)
                        .padding(6)
                        .background(TurboTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

            TaskStatusRowIndicator(
                status: context.task.status,
                jobColor: context.jobColor,
                diameter: 14
            )

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.task.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let line = planLine {
                        Text(line)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(overdue ? Color.red.opacity(0.92) : TurboTheme.mutedInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEditDates) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.65))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trainingWheelsTooltip("Edit start / target end dates")

            Button(action: onToggleNow) {
                Image(systemName: context.task.isScheduledNow ? "bolt.fill" : "bolt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        context.task.isScheduledNow ? context.jobColor : TurboTheme.mutedInk.opacity(0.4)
                    )
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trainingWheelsTooltip(context.task.isScheduledNow ? "Remove from Now" : "Add to Now")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? TurboTheme.accentSoft.opacity(0.45) : Color.clear)
        .shadow(color: overdue ? Color.red.opacity(0.45) : .clear, radius: overdue ? 6 : 0, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(overdue ? Color.red.opacity(0.55) : Color.clear, lineWidth: 1)
                .padding(1)
        )
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEditTask)
                .environmentObject(store)
        }
    }

    private var planLine: String? {
        let fmt = Date.FormatStyle(date: .abbreviated, time: .omitted)
        switch (context.task.startDate, context.task.endDate) {
        case let (s?, e?):
            return "\(s.formatted(fmt)) → \(e.formatted(fmt))"
        case let (s?, nil):
            return "Starts \(s.formatted(fmt))"
        case let (nil, e?):
            return "Due \(e.formatted(fmt))"
        default:
            return nil
        }
    }
}

// MARK: - Plan dates sheet

private struct TaskPlanDatesSheet: View {
    @EnvironmentObject private var store: TurboTaskStore
    @Environment(\.dismiss) private var dismiss

    let payload: TaskDateEditPayload

    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Plan dates")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Plan dates",
                    message: "These dates are informational. Past due is shown on the project board when the task is not done."
                )
            }
            .padding(.bottom, 16)

            Form {
                Toggle("Start date", isOn: $hasStart)
                if hasStart {
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                }
                Toggle("Target end", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Ends", selection: $end, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .trainingWheelsTooltip("Discard changes · Esc")
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .trainingWheelsTooltip("Apply dates · Return")
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(minWidth: 340)
        .onAppear {
            guard let ctx = store.taskContext(jobID: payload.jobID, projectID: payload.projectID, taskID: payload.id) else {
                return
            }
            hasStart = ctx.task.startDate != nil
            hasEnd = ctx.task.endDate != nil
            if let s = ctx.task.startDate { start = s }
            if let e = ctx.task.endDate { end = e }
        }
    }

    private func save() {
        guard let ctx = store.taskContext(jobID: payload.jobID, projectID: payload.projectID, taskID: payload.id) else {
            dismiss()
            return
        }
        store.updateTask(context: ctx) { task in
            task.startDate = hasStart ? Calendar.current.startOfDay(for: start) : nil
            task.endDate = hasEnd ? Calendar.current.startOfDay(for: end) : nil
        }
        dismiss()
    }
}
