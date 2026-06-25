//
//  ProjectsView.swift
//  Turbotask
//
//  Two-pane portfolio: field pill · project rows · detail. Matches the Operations tab.
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

// MARK: - Control surface helper

private extension View {
    func portfolioControlSurface(cornerRadius: CGFloat = 8) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
    }
}

// MARK: - Root

struct ProjectsView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var focusedJobID: UUID?
    @State private var editingTask: TaskContext?
    @State private var dateEditPayload: TaskDateEditPayload?
    @State private var pendingDeleteProject: ProjectContext?
    @State private var showFieldEditor = false
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

    private var focusedJob: Job? {
        focusedJobID.flatMap { id in store.jobs.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            content
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
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
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            fieldSelector
            if focusedJobID != nil {
                fieldAppearanceButton
            }
            searchField
            Spacer(minLength: 8)
            sortMenu
            if let jid = focusedJobID {
                Button {
                    store.openNewProject(preferredJobID: jid)
                } label: {
                    Label("New project", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(TurboTheme.ink)
                .trainingWheelsTooltip("New project on the selected field · ⌘⇧P")
            }
        }
    }

    private var fieldSelector: some View {
        Menu {
            ForEach(store.jobs) { job in
                Button {
                    focusedJobID = job.id
                } label: {
                    Label {
                        Text("\(job.title)  ·  \(store.projectCount(jobID: job.id))")
                    } icon: {
                        Image(systemName: focusedJobID == job.id ? "checkmark" : "circle.fill")
                    }
                }
            }
            if store.jobs.isEmpty {
                Button("New field…") { store.openComposer(.job) }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(focusedJob?.palette.color ?? TurboTheme.mutedInk)
                    .frame(width: 8, height: 8)
                Text(focusedJob?.title ?? "Choose field")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 11)
        .frame(height: 30)
        .portfolioControlSurface()
    }

    private var fieldAppearanceButton: some View {
        Button {
            showFieldEditor = true
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .portfolioControlSurface()
        .help("Rename field & change accent color")
        .popover(isPresented: $showFieldEditor, arrowEdge: .bottom) {
            if let jid = focusedJobID {
                FieldAppearanceEditor(jobID: jid, showsSummary: true)
                    .environmentObject(store)
                    .padding(16)
                    .frame(width: 280)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TurboTheme.mutedInk)
            TextField("Search projects", text: Binding(
                get: { store.projectsQuery.search },
                set: { val in _Concurrency.Task { @MainActor in store.projectsQuery.search = val } }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(TurboTheme.ink)
            if !projectSearchIsEmpty {
                Button {
                    _Concurrency.Task { @MainActor in store.projectsQuery.search = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: 260)
        .portfolioControlSurface()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TurboTaskStore.ProjectSortOption.allCases) { opt in
                Button {
                    _Concurrency.Task { @MainActor in store.projectsQuery.sort = opt }
                } label: {
                    Label(opt.title, systemImage: store.projectsQuery.sort == opt ? "checkmark" : sortSymbol(opt))
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .portfolioControlSurface()
        .help("Sort projects")
    }

    private func sortSymbol(_ opt: TurboTaskStore.ProjectSortOption) -> String {
        switch opt {
        case .manual: return "line.3.horizontal"
        case .openTasks: return "chart.bar"
        case .completion: return "checkmark.circle"
        case .title: return "textformat.abc"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty {
            VStack {
                TurboEmptyState(
                    title: "Create a field first.",
                    actionTitle: "New field",
                    action: { store.openComposer(.job) }
                )
                Spacer()
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                projectList
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(TurboTheme.divider.opacity(0.6))
                    .frame(width: 1)
                inspector
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var projectList: some View {
        if focusedJobID == nil {
            placeholder("Pick a field above.")
        } else if projectsInJob.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.6))
                Text(projectSearchIsEmpty ? "No projects in this field yet." : "No projects match your search.")
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                if projectSearchIsEmpty, let jid = focusedJobID {
                    Button("New project") { store.openNewProject(preferredJobID: jid) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(projectsInJob.enumerated()), id: \.element.project.id) { index, ctx in
                        PortfolioProjectRow(
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
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .id(ctx.project.id)
                    }
                    .onMove { source, destination in
                        guard store.projectsQuery.sort == .manual,
                              projectSearchIsEmpty,
                              let jid = focusedJobID else { return }
                        store.moveProjects(jobID: jid, fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.trailing, 12)
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

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(TurboTheme.mutedInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
    }

    @ViewBuilder
    private var inspector: some View {
        if let ctx = selectedContext {
            PortfolioInspector(
                context: ctx,
                onEditDates: { t in dateEditPayload = TaskDateEditPayload(context: t) },
                onEditTask: { editingTask = $0 },
                onRequestDeleteProject: { pendingDeleteProject = ctx }
            )
            .environmentObject(store)
            .padding(.leading, 18)
        } else {
            VStack(spacing: 6) {
                Text("Select a project")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                Text("Pick one on the left to see its tasks.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

// MARK: - Project row

private struct PortfolioProjectRow: View {
    let context: ProjectContext
    let isSelected: Bool
    var isTypeaheadFocus: Bool = false
    let onSelect: () -> Void
    let onRequestDelete: () -> Void

    private var percent: Int { Int((context.completionPercent * 100).rounded()) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? context.jobColor : context.jobColor.opacity(0.45))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 2)

                HStack(spacing: 10) {
                    if !context.project.iconEmoji.isEmpty {
                        Text(context.project.iconEmoji)
                            .font(.system(size: 15))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.project.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(TurboTheme.ink)
                            .lineLimit(1)
                        if !context.project.outcome.isEmpty {
                            Text(context.project.outcome)
                                .font(.system(size: 11.5))
                                .foregroundStyle(TurboTheme.mutedInk)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(percent)%")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(percent > 0 ? TurboTheme.ink : TurboTheme.mutedInk)
                        TurboProgressBar(value: context.completionPercent, tint: context.jobColor)
                            .frame(width: 66, height: 3)
                        Text("\(context.openTaskCount) open · \(context.doneTaskCount) done")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? TurboTheme.rowSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: isSelected || isTypeaheadFocus ? 1 : 0)
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
        if isSelected { return TurboTheme.cardStroke.opacity(0.7) }
        if isTypeaheadFocus { return TurboTheme.ink.opacity(0.3) }
        return Color.clear
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TurboTheme.ink)

                        TextField(
                            "Outcome — what done looks like",
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
                        .font(.system(size: 12.5))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1...5)
                    }
                }

                TurboProgressBar(value: context.completionPercent, tint: context.jobColor)
                    .frame(height: 4)

                Rectangle().fill(TurboTheme.divider.opacity(0.6)).frame(height: 1)

                HStack {
                    Text("TASKS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(TurboTheme.mutedInk)
                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
                    Spacer()
                    Button {
                        store.select(.project(jobID: context.jobID, projectID: context.project.id))
                        store.openComposer(.task)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TurboTheme.mutedInk)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(TurboTheme.nestedCardFill)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(TurboTheme.cardStroke.opacity(0.7), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("New task in this project")
                }

                if tasks.isEmpty {
                    Text("No tasks yet.")
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
                        .padding(.vertical, 8)
                } else {
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
                }

                Rectangle().fill(TurboTheme.divider.opacity(0.6)).frame(height: 1)

                Button("Delete project…", role: .destructive) {
                    onRequestDeleteProject()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(TurboTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
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

            VStack(alignment: .leading, spacing: 2) {
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

                TaskSubtasksView(context: context, style: .list, maxVisible: 3)
                    .environmentObject(store)
            }
                .frame(maxWidth: .infinity, alignment: .leading)

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
