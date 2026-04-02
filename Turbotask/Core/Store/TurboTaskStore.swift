//
//  TurboTaskStore.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TurboTaskStore: ObservableObject {
    private struct TaskScopeKey: Hashable {
        var jobID: UUID?
        var projectID: UUID?
    }

    private enum TaskStorageLocation {
        case standalone(taskIndex: Int)
        case job(jobIndex: Int, taskIndex: Int)
        case project(jobIndex: Int, projectIndex: Int, taskIndex: Int)
    }

    private struct JobIndexEntry {
        var searchText: String
        var openWorkCount: Int
        var projectCount: Int
    }

    enum Screen: String, CaseIterable, Identifiable {
        case now
        case projects
        case tasks
        case jobs
        case metrics
        case settings

        var id: String { rawValue }

        static var primaryCases: [Screen] {
            [.now, .projects, .tasks, .jobs, .metrics]
        }

        var title: String {
            switch self {
            case .now:
                "Now"
            case .projects:
                "Projects"
            case .tasks:
                "Tasks"
            case .jobs:
                "Jobs"
            case .metrics:
                "Metrics"
            case .settings:
                "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .now:
                "bolt.circle"
            case .projects:
                "square.stack.3d.up"
            case .tasks:
                "checklist"
            case .jobs:
                "briefcase"
            case .metrics:
                "chart.line.uptrend.xyaxis"
            case .settings:
                "gearshape"
            }
        }
    }

    enum Selection: Hashable {
        case job(UUID)
        case project(jobID: UUID, projectID: UUID)
        /// `projectID == nil` means the task lives on the job outside any project; both IDs nil means a standalone task.
        case task(jobID: UUID?, projectID: UUID?, taskID: UUID)
    }

    enum ComposerKind {
        case job
        case project
        case task
    }

    /// Dispatched from the menu bar so Now actions work from any screen; `NowView` consumes and clears.
    enum NowShortcutAction: Equatable {
        case focusQuickAdd
        case toggleViewMode
        case openEditorForSelection
        case startSelectedTask
        case pauseSelectedTask
        case markSelectedDone
        case markSelectedWaiting
    }

    struct ComposerContext: Identifiable {
        let id = UUID()
        var kind: ComposerKind
        var preferredJobID: UUID?
        var preferredProjectID: UUID?
        var scheduleForNow: Bool
    }

    enum ProjectSortOption: String, CaseIterable, Identifiable {
        case openTasks
        case completion
        case title
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openTasks:
                "Open"
            case .completion:
                "Completion"
            case .title:
                "Title"
            case .manual:
                "Manual"
            }
        }
    }

    struct ProjectsQuery: Equatable {
        var search = ""
        var sort: ProjectSortOption = .openTasks
    }

    enum TaskSortOption: String, CaseIterable, Identifiable {
        case priority
        case title
        case status
        case project

        var id: String { rawValue }

        var title: String {
            switch self {
            case .priority:
                "Priority"
            case .title:
                "Title"
            case .status:
                "Status"
            case .project:
                "Project"
            }
        }
    }

    struct TasksQuery: Equatable {
        var search = ""
        var jobID: UUID?
        var projectID: UUID?
        var status: TaskStatus?
        var energy: TaskEnergy?
        var onlyNow = false
        var sort: TaskSortOption = .priority
    }

    @Published var selectedScreen: Screen = .now {
        didSet {
            scheduleNowRowFlashSync()
        }
    }
    @Published var jobs: [Job] {
        didSet {
            derivedStateIsDirty = true
            schedulePersistenceIfNeeded()
        }
    }

    @Published var standaloneTasks: [Task] {
        didSet {
            derivedStateIsDirty = true
            schedulePersistenceIfNeeded()
        }
    }
    @Published var history: [ActivityEvent] {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var dailyCapacityMinutes: Int {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var themeMode: AppThemeMode {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowPinnedJobIDs: [UUID] {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowPinnedProjectIDs: [UUID] {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowSuppressedJobIDs: [UUID] {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowSuppressedProjectIDs: [UUID] {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var focusCardDensity: FocusCardDensity {
        didSet {
            if persistenceEnabled, oldValue != focusCardDensity {
                schedulePersistenceIfNeeded()
            }
        }
    }
    @Published var trainingWheelsEnabled: Bool {
        didSet {
            if persistenceEnabled, oldValue != trainingWheelsEnabled {
                schedulePersistenceIfNeeded()
            }
        }
    }
    @Published var typeaheadListNavigationEnabled: Bool {
        didSet {
            if persistenceEnabled, oldValue != typeaheadListNavigationEnabled {
                schedulePersistenceIfNeeded()
            }
        }
    }
    @Published var tasksPresentation = TasksPresentationState() {
        didSet {
            guard persistenceEnabled, oldValue != tasksPresentation else { return }
            schedulePersistenceIfNeeded()
        }
    }
    @Published var projectsQuery = ProjectsQuery()
    @Published var tasksQuery = TasksQuery()
    @Published var isFocusOverlayVisible = false
    @Published var selection: Selection? {
        didSet {
            scheduleNowRowFlashSync()
        }
    }

    /// Brief highlight on the Now list for the task keyboard / click targeting (not persistent “selected” grey).
    @Published private(set) var nowRowFlashTaskID: UUID?
    private var nowRowFlashWorkItem: DispatchWorkItem?
    private var pendingNowRowFlashSync = false
    @Published var composer: ComposerContext?
    @Published var nowShortcutAction: NowShortcutAction?

    private let persistenceEnabled: Bool
    private let calendar = Calendar(identifier: .iso8601)
    private var derivedStateIsDirty = true
    private var cachedTaskContexts: [TaskContext] = []
    private var cachedProjectContexts: [ProjectContext] = []
    private var cachedTasksByID: [UUID: TaskContext] = [:]
    private var cachedProjectsByID: [UUID: ProjectContext] = [:]
    private var cachedJobsByID: [UUID: Job] = [:]
    private var cachedTaskContextsByScope: [TaskScopeKey: [TaskContext]] = [:]
    private var cachedProjectContextsByJobID: [UUID: [ProjectContext]] = [:]
    private var cachedJobIndex: [UUID: JobIndexEntry] = [:]
    private var cachedNowTasks: [TaskContext] = []
    private var cachedActiveTasks: [TaskContext] = []
    private var cachedOpenTaskCount = 0
    private var cachedCompletionCount = 0
    private var cachedWaitingTaskCount = 0
    private var cachedPlan = ExecutionPlan.empty

    init(
        jobs: [Job],
        standaloneTasks: [Task] = [],
        history: [ActivityEvent],
        dailyCapacityMinutes: Int = 540,
        themeMode: AppThemeMode = .system,
        nowPinnedJobIDs: [UUID] = [],
        nowPinnedProjectIDs: [UUID] = [],
        nowSuppressedJobIDs: [UUID] = [],
        nowSuppressedProjectIDs: [UUID] = [],
        focusCardDensity: FocusCardDensity = .standard,
        trainingWheelsEnabled: Bool = true,
        typeaheadListNavigationEnabled: Bool = true,
        tasksPresentation: TasksPresentationState? = nil,
        persistenceEnabled: Bool = true
    ) {
        self.jobs = jobs
        self.standaloneTasks = standaloneTasks
        self.history = history.sorted(by: { $0.timestamp > $1.timestamp })
        self.dailyCapacityMinutes = dailyCapacityMinutes
        self.themeMode = themeMode
        self.nowPinnedJobIDs = nowPinnedJobIDs
        self.nowPinnedProjectIDs = nowPinnedProjectIDs
        self.nowSuppressedJobIDs = nowSuppressedJobIDs
        self.nowSuppressedProjectIDs = nowSuppressedProjectIDs
        self.focusCardDensity = focusCardDensity
        self.trainingWheelsEnabled = trainingWheelsEnabled
        self.typeaheadListNavigationEnabled = typeaheadListNavigationEnabled
        self.tasksPresentation = tasksPresentation ?? TasksPresentationState()
        self.persistenceEnabled = persistenceEnabled
        rebuildDerivedState()
    }

    static func bootstrap() -> TurboTaskStore {
        switch WorkspacePersistence.loadOutcome() {
        case .loaded(let snapshot), .recoveredFromBackup(let snapshot):
            let store = TurboTaskStore(
                jobs: snapshot.jobs,
                standaloneTasks: snapshot.standaloneTasks,
                history: snapshot.history,
                dailyCapacityMinutes: snapshot.dailyCapacityMinutes,
                themeMode: snapshot.themeMode,
                nowPinnedJobIDs: snapshot.nowPinnedJobIDs,
                nowPinnedProjectIDs: snapshot.nowPinnedProjectIDs,
                nowSuppressedJobIDs: snapshot.nowSuppressedJobIDs,
                nowSuppressedProjectIDs: snapshot.nowSuppressedProjectIDs,
                focusCardDensity: snapshot.focusCardDensity,
                trainingWheelsEnabled: snapshot.trainingWheelsEnabled,
                typeaheadListNavigationEnabled: snapshot.typeaheadListNavigationEnabled,
                tasksPresentation: snapshot.tasksPresentation
            )
            store.ensureSelection()
            return store
        case .noWorkspace:
            let store = bootstrapFallbackStore()
            store.ensureSelection()
            return store
        case .unrecoverable:
            return emptyWorkspaceStore()
        }
    }

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            jobs: jobs,
            standaloneTasks: standaloneTasks,
            history: history,
            dailyCapacityMinutes: dailyCapacityMinutes,
            tasksPresentation: tasksPresentation,
            themeMode: themeMode,
            nowPinnedJobIDs: nowPinnedJobIDs,
            nowPinnedProjectIDs: nowPinnedProjectIDs,
            nowSuppressedJobIDs: nowSuppressedJobIDs,
            nowSuppressedProjectIDs: nowSuppressedProjectIDs,
            focusCardDensity: focusCardDensity,
            trainingWheelsEnabled: trainingWheelsEnabled,
            typeaheadListNavigationEnabled: typeaheadListNavigationEnabled
        )
    }

    var taskContexts: [TaskContext] {
        ensureDerivedState()
        return cachedTaskContexts
    }

    var projectContexts: [ProjectContext] {
        ensureDerivedState()
        return cachedProjectContexts
    }

    var activeTask: TaskContext? {
        ensureDerivedState()
        return cachedActiveTasks.first
    }

    /// All in-progress tasks (multiple when using compatible multitask modes).
    var activeTasks: [TaskContext] {
        ensureDerivedState()
        return cachedActiveTasks
    }

    /// Scheduled-for-now tasks: incomplete first, then completed (still on Now until unpinned).
    var nowTasks: [TaskContext] {
        ensureDerivedState()
        return cachedNowTasks
    }

    var plan: ExecutionPlan {
        ensureDerivedState()
        return cachedPlan
    }

    var currentFocusGroup: [TaskContext] {
        plan.focusGroup
    }

    var nextTask: TaskContext? {
        plan.next
    }

    var preferredColorScheme: ColorScheme? {
        themeMode.colorScheme
    }

    var completionCount: Int {
        ensureDerivedState()
        return cachedCompletionCount
    }

    var waitingTaskCount: Int {
        ensureDerivedState()
        return cachedWaitingTaskCount
    }

    var openTaskCount: Int {
        ensureDerivedState()
        return cachedOpenTaskCount
    }

    var focusRatingAverage: Double {
        let ratings = history.compactMap(\.focusRating)
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    var qualityRatingAverage: Double {
        let ratings = history.compactMap(\.qualityRating)
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    var filteredProjectContexts: [ProjectContext] {
        let query = projectsQuery.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = projectContexts.filter { context in
            guard !query.isEmpty else { return true }
            return context.project.title.lowercased().contains(query)
                || context.project.outcome.lowercased().contains(query)
                || context.jobTitle.lowercased().contains(query)
        }

        switch projectsQuery.sort {
        case .openTasks:
            return filtered.sorted {
                if $0.openTaskCount != $1.openTaskCount {
                    return $0.openTaskCount > $1.openTaskCount
                }
                return $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending
            }
        case .completion:
            return filtered.sorted {
                if $0.completionPercent != $1.completionPercent {
                    return $0.completionPercent < $1.completionPercent
                }
                return $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending
            }
        case .title:
            return filtered.sorted {
                $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending
            }
        case .manual:
            return filtered
        }
    }

    var filteredTaskContexts: [TaskContext] {
        taskContexts
            .filter(matchesTaskQuery)
            .sorted(by: sortTaskList)
    }

    var visibleTaskFieldsInDisplayOrder: [TaskVisibleField] {
        TaskVisibleField.allCases.filter { tasksPresentation.visibleFields.contains($0) }
    }

    var filteredTaskContextsByStatus: [(status: TaskStatus, contexts: [TaskContext])] {
        TaskStatus.allCases.map { status in
            (
                status: status,
                contexts: filteredTaskContexts.filter { $0.task.status == status }
            )
        }
    }

    var selectedJobID: UUID? {
        switch selection {
        case .job(let jobID):
            jobID
        case .project(let jobID, _):
            jobID
        case .task(let jobID, _, _):
            jobID
        case nil:
            nil
        }
    }

    var selectedProjectID: UUID? {
        switch selection {
        case .project(_, let projectID):
            projectID
        case .task(_, let projectID, _):
            projectID
        default:
            nil
        }
    }

    var selectedTaskID: UUID? {
        if case .task(_, _, let taskID) = selection {
            return taskID
        }
        return nil
    }

    var selectedJob: Job? {
        guard let selectedJobID else { return nil }
        ensureDerivedState()
        return cachedJobsByID[selectedJobID]
    }

    var selectedProjectContext: ProjectContext? {
        guard let selectedProjectID else { return nil }
        ensureDerivedState()
        return cachedProjectsByID[selectedProjectID]
    }

    var selectedTaskContext: TaskContext? {
        guard let selectedTaskID else { return nil }
        return taskContext(taskID: selectedTaskID)
    }

    func projectContext(jobID: UUID, projectID: UUID) -> ProjectContext? {
        ensureDerivedState()
        guard let context = cachedProjectsByID[projectID], context.jobID == jobID else { return nil }
        return context
    }

    func taskContext(taskID: UUID) -> TaskContext? {
        ensureDerivedState()
        return cachedTasksByID[taskID]
    }

    func taskContext(jobID: UUID?, projectID: UUID?, taskID: UUID) -> TaskContext? {
        ensureDerivedState()
        guard let context = cachedTasksByID[taskID] else { return nil }
        guard context.jobID == jobID, context.projectID == projectID else { return nil }
        return context
    }

    func taskContexts(jobID: UUID, projectID: UUID) -> [TaskContext] {
        ensureDerivedState()
        return cachedTaskContextsByScope[TaskScopeKey(jobID: jobID, projectID: projectID)] ?? []
    }

    func jobLevelTaskContexts(jobID: UUID) -> [TaskContext] {
        ensureDerivedState()
        return cachedTaskContextsByScope[TaskScopeKey(jobID: jobID, projectID: nil)] ?? []
    }

    func projectContexts(jobID: UUID) -> [ProjectContext] {
        ensureDerivedState()
        return cachedProjectContextsByJobID[jobID] ?? []
    }

    func projectCount(jobID: UUID) -> Int {
        ensureDerivedState()
        return cachedJobIndex[jobID]?.projectCount ?? 0
    }

    func jobOpenWorkCount(jobID: UUID) -> Int {
        ensureDerivedState()
        return cachedJobIndex[jobID]?.openWorkCount ?? 0
    }

    func jobSearchText(jobID: UUID) -> String {
        ensureDerivedState()
        return cachedJobIndex[jobID]?.searchText ?? ""
    }

    func job(id: UUID) -> Job? {
        ensureDerivedState()
        return cachedJobsByID[id]
    }

    func ensureSelection() {
        guard selection == nil else { return }

        if let activeTask {
            selection = .task(jobID: activeTask.jobID, projectID: activeTask.projectID, taskID: activeTask.task.id)
            return
        }

        if let firstNowTask = nowTasks.first(where: { $0.task.status != .done }) {
            selection = .task(jobID: firstNowTask.jobID, projectID: firstNowTask.projectID, taskID: firstNowTask.task.id)
            return
        }

        if let firstJob = jobs.first {
            selection = .job(firstJob.id)
        }
    }

    func select(_ selection: Selection?) {
        self.selection = selection
    }

    private func scheduleNowRowFlashSync() {
        guard !pendingNowRowFlashSync else { return }
        pendingNowRowFlashSync = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingNowRowFlashSync = false
            self.syncNowRowFlashWithSelection()
        }
    }

    private func syncNowRowFlashWithSelection() {
        guard selectedScreen == .now else {
            clearNowRowFlash()
            return
        }
        switch selection {
        case let .task(jobID, projectID, taskID):
            let inScope = scopedNowTasks.contains {
                $0.task.id == taskID && $0.jobID == jobID && $0.projectID == projectID
            }
            if inScope {
                pulseNowRowFlash(taskID: taskID)
            } else {
                clearNowRowFlash()
            }
        case .none, .job, .project:
            clearNowRowFlash()
        }
    }

    private func pulseNowRowFlash(taskID: UUID) {
        nowRowFlashWorkItem?.cancel()
        if nowRowFlashTaskID != taskID {
            nowRowFlashTaskID = taskID
        }
        let captured = taskID
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.nowRowFlashTaskID == captured {
                self.nowRowFlashTaskID = nil
            }
        }
        nowRowFlashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    func clearNowRowFlash() {
        nowRowFlashWorkItem?.cancel()
        nowRowFlashWorkItem = nil
        guard nowRowFlashTaskID != nil else { return }
        nowRowFlashTaskID = nil
    }

    /// Moves selection among `scopedNowTasks` (same order as the Now list: open, then done).
    func moveNowSelection(_ step: Int) {
        let tasks = scopedNowTasks
        guard !tasks.isEmpty else { return }

        func matchesSelection(_ ctx: TaskContext) -> Bool {
            guard case let .task(j, p, tid) = selection else { return false }
            return ctx.task.id == tid && ctx.jobID == j && ctx.projectID == p
        }

        let index: Int
        if let i = tasks.firstIndex(where: matchesSelection) {
            index = i
        } else if let first = tasks.first {
            select(.task(jobID: first.jobID, projectID: first.projectID, taskID: first.task.id))
            return
        } else {
            return
        }

        let next = index + step
        guard tasks.indices.contains(next) else { return }
        let ctx = tasks[next]
        select(.task(jobID: ctx.jobID, projectID: ctx.projectID, taskID: ctx.task.id))
    }

    func openComposer(_ kind: ComposerKind, scheduleForNow: Bool = false) {
        let (preferredJobID, preferredProjectID): (UUID?, UUID?) = {
            switch kind {
            case .task:
                guard let jid = selectedJobID else {
                    return (nil, nil)
                }
                if let pid = selectedProjectID,
                   projectContexts.contains(where: { $0.jobID == jid && $0.project.id == pid }) {
                    return (jid, pid)
                }
                return (jid, nil)
            case .project:
                return (selectedJobID, nil)
            case .job:
                return (nil, nil)
            }
        }()

        composer = ComposerContext(
            kind: kind,
            preferredJobID: preferredJobID,
            preferredProjectID: preferredProjectID,
            scheduleForNow: scheduleForNow
        )
    }

    func performNowShortcut(_ action: NowShortcutAction) {
        selectedScreen = .now
        nowShortcutAction = action
    }

    func clearNowShortcutAction() {
        nowShortcutAction = nil
    }

    func clearComposer() {
        composer = nil
    }

    func setTaskViewMode(_ mode: TaskViewMode) {
        tasksPresentation.viewMode = mode
    }

    func isTaskFieldVisible(_ field: TaskVisibleField) -> Bool {
        tasksPresentation.visibleFields.contains(field)
    }

    func toggleTaskFieldVisibility(_ field: TaskVisibleField) {
        if tasksPresentation.visibleFields.contains(field) {
            tasksPresentation.visibleFields.remove(field)
        } else {
            tasksPresentation.visibleFields.insert(field)
        }
    }

    func resetTaskFieldVisibility() {
        tasksPresentation.visibleFields = TasksPresentationState.defaultVisibleFields
    }

    func addJob(title: String, summary: String, palette: JobPalette) {
        let job = Job(title: title, summary: summary, palette: palette, projects: [])
        jobs.append(job)
        selection = .job(job.id)
        persist()
    }

    func addProject(title: String, outcome: String, iconEmoji: String, jobID: UUID) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let project = Project(title: title, outcome: outcome, tasks: [], iconEmoji: iconEmoji)
        jobs[jobIndex].projects.append(project)
        selection = .project(jobID: jobID, projectID: project.id)
        persist()
    }

    func openNewProject(preferredJobID: UUID?) {
        composer = ComposerContext(kind: .project, preferredJobID: preferredJobID, preferredProjectID: nil, scheduleForNow: false)
    }

    func addTask(
        title: String,
        status: TaskStatus,
        energy: TaskEnergy,
        cadence: TaskCadence,
        isScheduledNow: Bool,
        repeatEveryMinutes: Int?,
        kpiTarget: Int?,
        kpiUnit: String?,
        toolBundleIDs: [String] = [],
        jobID: UUID?,
        projectID: UUID?,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        let task = Task(
            title: title,
            summary: "",
            why: "",
            energy: energy,
            cadence: cadence,
            status: status,
            progress: 0,
            estimatedMinutes: 30,
            isScheduledNow: isScheduledNow,
            nowOrder: isScheduledNow ? nextNowOrder() : 0,
            priority: 3,
            waitingOn: nil,
            nextStep: "",
            repeatEveryMinutes: cadence == .oneOff ? nil : repeatEveryMinutes,
            kpiTarget: cadence == .kpi ? kpiTarget : nil,
            kpiUnit: cadence == .kpi ? emptyToNil(kpiUnit) : nil,
            toolBundleIDs: toolBundleIDs,
            startDate: startDate,
            endDate: endDate
        )

        if let jobID {
            guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            if let projectID {
                guard let projectIndex = jobs[jobIndex].projects.firstIndex(where: { $0.id == projectID }) else { return }
                jobs[jobIndex].projects[projectIndex].tasks.append(task)
            } else {
                jobs[jobIndex].jobTasks.append(task)
            }
            selection = .task(jobID: jobID, projectID: projectID, taskID: task.id)
        } else {
            standaloneTasks.append(task)
            selection = .task(jobID: nil, projectID: nil, taskID: task.id)
        }

        persist()
    }

    func updateSelectedJob(_ mutate: (inout Job) -> Void) {
        guard case .job(let jobID) = selection ?? .job(UUID()) else { return }
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[jobIndex])
        persist()
    }

    func updateJob(jobID: UUID, mutate: (inout Job) -> Void) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[jobIndex])
        persist()
    }

    func updateSelectedProject(_ mutate: (inout Project) -> Void) {
        guard let selectedProjectContext,
              let location = projectLocation(jobID: selectedProjectContext.jobID, projectID: selectedProjectContext.project.id) else {
            return
        }
        mutate(&jobs[location.jobIndex].projects[location.projectIndex])
        persist()
    }

    func updateProject(jobID: UUID, projectID: UUID, mutate: (inout Project) -> Void) {
        guard let location = projectLocation(jobID: jobID, projectID: projectID) else { return }
        mutate(&jobs[location.jobIndex].projects[location.projectIndex])
        persist()
    }

    func updateSelectedTask(_ mutate: (inout Task) -> Void) {
        guard let selectedTaskContext else { return }
        updateTask(taskID: selectedTaskContext.task.id, mutate: mutate)
        persist()
    }

    func updateTask(context: TaskContext, mutate: (inout Task) -> Void) {
        updateTask(
            context: context,
            destinationJobID: context.jobID,
            destinationProjectID: context.projectID,
            mutate: mutate
        )
    }

    @discardableResult
    func updateTask(
        context: TaskContext,
        destinationJobID: UUID?,
        destinationProjectID: UUID?,
        mutate: (inout Task) -> Void
    ) -> Bool {
        let normalizedProjectID = destinationJobID == nil ? nil : destinationProjectID
        let destinationChanged = context.jobID != destinationJobID || context.projectID != normalizedProjectID

        if destinationChanged {
            guard let location = taskStorageLocation(taskID: context.task.id) else { return false }

            var task = removeTask(at: location)
            mutate(&task)

            guard insertTask(task, jobID: destinationJobID, projectID: normalizedProjectID) else {
                _ = insertTask(task, jobID: context.jobID, projectID: context.projectID)
                persist()
                return false
            }

            selection = .task(jobID: destinationJobID, projectID: normalizedProjectID, taskID: task.id)
            persist()
            return true
        }

        updateTask(taskID: context.task.id, mutate: mutate)
        selection = .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
        persist()
        return true
    }

    /// Selects this task in the single selection model (Now focus, row highlight, etc.).
    func selectTask(_ context: TaskContext) {
        select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
    }

    func deleteTask(context: TaskContext) {
        let tid = context.task.id

        if let sIdx = standaloneTasks.firstIndex(where: { $0.id == tid }) {
            standaloneTasks.remove(at: sIdx)
        } else if let jid = context.jobID, let jidx = jobs.firstIndex(where: { $0.id == jid }) {
            if let tidx = jobs[jidx].jobTasks.firstIndex(where: { $0.id == tid }) {
                jobs[jidx].jobTasks.remove(at: tidx)
            } else if let pid = context.projectID,
                      let pidx = jobs[jidx].projects.firstIndex(where: { $0.id == pid }),
                      let tidx = jobs[jidx].projects[pidx].tasks.firstIndex(where: { $0.id == tid }) {
                jobs[jidx].projects[pidx].tasks.remove(at: tidx)
            } else {
                return
            }
        } else {
            return
        }

        history.removeAll { $0.taskID == tid }
        if case .task(_, _, let selectedID) = selection, selectedID == tid {
            selection = nil
            ensureSelection()
        }
        persist()
    }

    func moveJobs(fromOffsets source: IndexSet, toOffset destination: Int) {
        jobs.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
    }

    func moveProjects(jobID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[jobIndex].projects.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
    }

    func deleteJob(_ jobID: UUID) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        let job = jobs[jobIndex]
        let taskIDs = Set(
            job.jobTasks.map(\.id) + job.projects.flatMap(\.tasks).map(\.id)
        )
        jobs.remove(at: jobIndex)
        history.removeAll { event in
            guard let taskID = event.taskID else { return false }
            return taskIDs.contains(taskID)
        }

        if selectedJobID == jobID {
            selection = nil
            ensureSelection()
        }

        persist()
    }

    func deleteProject(jobID: UUID, projectID: UUID) {
        guard let location = projectLocation(jobID: jobID, projectID: projectID) else { return }

        let project = jobs[location.jobIndex].projects[location.projectIndex]
        let taskIDs = Set(project.tasks.map(\.id))

        history.removeAll { event in
            guard let tid = event.taskID else { return false }
            return taskIDs.contains(tid)
        }

        nowPinnedProjectIDs.removeAll { $0 == projectID }

        jobs[location.jobIndex].projects.remove(at: location.projectIndex)

        switch selection {
        case .project(let j, let p) where j == jobID && p == projectID:
            if let first = jobs[location.jobIndex].projects.first {
                selection = .project(jobID: jobID, projectID: first.id)
            } else {
                selection = .job(jobID)
            }
        case .task(let j, let p, _) where j == jobID && p == projectID:
            selection = nil
            ensureSelection()
        case .task(_, _, let tid) where taskIDs.contains(tid):
            selection = nil
            ensureSelection()
        default:
            break
        }

        persist()
    }

    func setTaskStatus(_ context: TaskContext, status: TaskStatus) {
        let priorActives = activeTasks

        if status == .active {
            reconcileParallelActivesForActivating(context)
        }

        let wasOneOff = context.task.cadence == .oneOff

        updateTask(taskID: context.task.id) { task in
            if status == .done, task.cadence != .oneOff {
                task.progress = 0
                task.status = .queued
                task.nextAvailableAt = task.repeatEveryMinutes.map { .now.addingTimeInterval(Double($0 * 60)) }
            } else if status == .active && task.progress == 0 {
                task.status = status
                task.progress = 0.1
                task.nextAvailableAt = nil
            } else {
                task.status = status
                task.nextAvailableAt = nil
                if status == .done {
                    task.progress = 1
                }
            }
        }

        if status == .done, wasOneOff {
            updateTask(taskID: context.task.id) { task in
                guard task.status == .done else { return }
                task.nowOrder = nextNowOrder()
            }
        }

        if status == .active, !context.task.energy.isMultitaskable {
            let others = priorActives.filter { $0.task.id != context.task.id }
            if let first = others.first {
                appendEvent(kind: .switched, context: first, detail: "Switched into \(context.task.title.lowercased()).")
            }
        }

        switch status {
        case .active:
            appendEvent(kind: .started, context: context, detail: "Started focus block.")
        case .paused:
            appendEvent(kind: .paused, context: context, detail: "Paused to protect the active thread.")
        case .waiting:
            appendEvent(kind: .waiting, context: context, detail: context.task.waitingOn ?? "Waiting on external progress.")
        case .done:
            if context.task.cadence == .oneOff {
                appendEvent(kind: .completed, context: context, detail: "Completed.")
                appendReflectionIfNeeded(for: context)
            } else {
                let resetCopy = taskContext(taskID: context.task.id) ?? context
                appendEvent(
                    kind: .completed,
                    context: resetCopy,
                    detail: repeatableCompletionDetail(for: resetCopy.task)
                )
            }
        case .queued:
            break
        }

        selection = .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
        if status == .active {
            moveNowTaskToTop(taskID: context.task.id)
        }
        persist()
    }

    /// Uses the current `selection` task (any screen). No-op if selection is not a task.
    func applyStatusToSelectedTask(_ status: TaskStatus) {
        guard let ctx = selectedTaskContext else { return }
        setTaskStatus(ctx, status: status)
    }

    func incrementProgress(_ context: TaskContext, by amount: Double = 0.15) {
        updateTask(taskID: context.task.id) { task in
            task.progress = min(task.progress + amount, 1)
            if task.progress >= 1 {
                task.status = .done
            }
        }

        if let refreshed = taskContexts.first(where: { $0.id == context.id }), refreshed.task.status == .done {
            setTaskStatus(refreshed, status: .done)
            return
        }

        persist()
    }

    func toggleTaskNow(_ context: TaskContext) {
        updateTask(taskID: context.task.id) { task in
            task.isScheduledNow.toggle()
            if task.isScheduledNow {
                task.nowOrder = nextNowOrder()
            }
        }
        persist()
    }

    /// Puts this task first in the Now list (by renumbering `nowOrder`) when it becomes in progress.
    private func moveNowTaskToTop(taskID: UUID) {
        var ordered = nowTasks
        guard let index = ordered.firstIndex(where: { $0.task.id == taskID }),
              index > 0 else { return }

        let moving = ordered.remove(at: index)
        ordered.insert(moving, at: 0)

        for (position, ctx) in ordered.enumerated() {
            updateTask(taskID: ctx.task.id) { task in
                task.nowOrder = Double(position)
            }
        }
    }

    func reorderNowTask(_ movingTaskID: UUID, before targetTaskID: UUID) {
        guard movingTaskID != targetTaskID else { return }

        let originalIDs = nowTasks.map(\.task.id)
        var ordered = nowTasks
        guard let sourceIndex = ordered.firstIndex(where: { $0.task.id == movingTaskID }),
              let destinationIndex = ordered.firstIndex(where: { $0.task.id == targetTaskID }) else {
            return
        }

        let moving = ordered.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        ordered.insert(moving, at: insertionIndex)

        if ordered.map(\.task.id) == originalIDs {
            return
        }

        for (index, context) in ordered.enumerated() {
            updateTask(taskID: context.task.id) { task in
                task.nowOrder = Double(index)
            }
        }

        persist()
    }

    /// Move a Now task to the end of the list (e.g. drop on trailing drop zone).
    func reorderNowTaskToEnd(_ movingTaskID: UUID) {
        var ordered = nowTasks
        guard let sourceIndex = ordered.firstIndex(where: { $0.task.id == movingTaskID }),
              sourceIndex < ordered.count - 1 else {
            return
        }

        let originalIDs = ordered.map(\.task.id)
        let moving = ordered.remove(at: sourceIndex)
        ordered.append(moving)

        if ordered.map(\.task.id) == originalIDs {
            return
        }

        for (index, context) in ordered.enumerated() {
            updateTask(taskID: context.task.id) { task in
                task.nowOrder = Double(index)
            }
        }

        persist()
    }

    func setDailyCapacityMinutes(_ minutes: Int) {
        dailyCapacityMinutes = minutes
        persist()
    }

    func setThemeMode(_ mode: AppThemeMode) {
        themeMode = mode
        if isFocusOverlayVisible {
            FocusOverlayController.shared.show(store: self)
        }
        persist()
    }

    func toggleOverlay() {
        if isFocusOverlayVisible {
            FocusOverlayController.shared.hide()
            isFocusOverlayVisible = false
        } else {
            FocusOverlayController.shared.show(store: self)
            isFocusOverlayVisible = true
        }
    }

    func activitySummary(daysBack: Int) -> [ActivitySummary] {
        let today = calendar.startOfDay(for: .now)

        return (0..<daysBack).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let items = history.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            return ActivitySummary(
                date: date,
                completions: items.filter { $0.kind == .completed }.count,
                focusAverage: average(items.compactMap(\.focusRating))
            )
        }
    }

    var automaticNowJobIDs: [UUID] {
        uniqueIDs(from: nowTasks.compactMap(\.jobID))
    }

    /// Jobs implied by Now tasks plus manual pins, before Today-bar suppressions.
    var mergedNowJobIDs: [UUID] {
        let automatic = automaticNowJobIDs
        let manual = nowPinnedJobIDs.filter { id in jobs.contains(where: { $0.id == id }) }
        return orderedUnion(primary: automatic, secondary: manual)
    }

    var visibleNowJobIDs: [UUID] {
        let suppressed = Set(nowSuppressedJobIDs)
        return mergedNowJobIDs.filter { !suppressed.contains($0) }
    }

    var visibleNowJobs: [Job] {
        visibleNowJobIDs.compactMap { id in
            jobs.first(where: { $0.id == id })
        }
    }

    var automaticNowProjectIDs: [UUID] {
        let baseJobIDs = Set(visibleNowJobIDs)
        let automatic = projectContexts
            .filter { context in
                guard baseJobIDs.contains(context.jobID) else { return false }
                return taskContexts(jobID: context.jobID, projectID: context.project.id).contains {
                    $0.task.isScheduledNow && $0.task.isAvailableNow
                }
            }
            .map(\.project.id)

        return uniqueIDs(from: automatic)
    }

    var mergedNowProjectIDs: [UUID] {
        let automatic = automaticNowProjectIDs
        let manual = nowPinnedProjectIDs.filter { id in
            projectContexts.contains(where: { $0.project.id == id })
        }
        return orderedUnion(primary: automatic, secondary: manual)
    }

    var visibleNowProjectIDs: [UUID] {
        let suppressed = Set(nowSuppressedProjectIDs)
        return mergedNowProjectIDs.filter { !suppressed.contains($0) }
    }

    var visibleNowProjects: [ProjectContext] {
        visibleNowProjectIDs.compactMap { projectID in
            projectContexts.first(where: { $0.project.id == projectID })
        }
    }

    var scopedNowTasks: [TaskContext] {
        let jobIDs = Set(visibleNowJobIDs)
        let projectIDs = Set(visibleNowProjectIDs)

        return nowTasks.filter { context in
            let matchesJob = jobIDs.isEmpty || (context.jobID.map { jobIDs.contains($0) } ?? true)
            let matchesProject = projectIDs.isEmpty || (context.projectID.map { projectIDs.contains($0) } ?? true)
            return matchesJob && matchesProject
        }
    }

    var workedMinutesToday: Int {
        let today = calendar.startOfDay(for: .now)
        let totals = Dictionary(grouping: history.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }) {
            $0.taskID ?? UUID()
        }

        return totals.values.reduce(0) { total, events in
            total + (events.compactMap(\.sessionMinutes).max() ?? 0)
        }
    }

    var workedMinutesRemaining: Int {
        max(dailyCapacityMinutes - workedMinutesToday, 0)
    }

    var workdayProgress: Double {
        guard dailyCapacityMinutes > 0 else { return 0 }
        return min(Double(workedMinutesToday) / Double(dailyCapacityMinutes), 1)
    }

    var nowTreeGroups: [[TaskContext]] {
        makeCompatibleNowGroups(from: scopedNowTasks.filter { $0.task.status != .done })
    }

    func pinNowJob(_ jobID: UUID) {
        nowSuppressedJobIDs.removeAll { $0 == jobID }
        guard !nowPinnedJobIDs.contains(jobID) else { return }
        nowPinnedJobIDs.append(jobID)
        persist()
    }

    /// Removes a job from the Today scope bar. If it was only showing because of Now tasks, it stays hidden until you add it again or clear suppression by pinning.
    func removeJobFromNowScope(_ jobID: UUID) {
        nowPinnedJobIDs.removeAll { $0 == jobID }
        if !nowSuppressedJobIDs.contains(jobID) {
            nowSuppressedJobIDs.append(jobID)
        }
        persist()
    }

    func pinNowProject(_ projectID: UUID) {
        nowSuppressedProjectIDs.removeAll { $0 == projectID }
        guard !nowPinnedProjectIDs.contains(projectID) else { return }
        nowPinnedProjectIDs.append(projectID)
        persist()
    }

    func removeProjectFromNowScope(_ projectID: UUID) {
        nowPinnedProjectIDs.removeAll { $0 == projectID }
        if !nowSuppressedProjectIDs.contains(projectID) {
            nowSuppressedProjectIDs.append(projectID)
        }
        persist()
    }

    private func matchesTaskQuery(_ context: TaskContext) -> Bool {
        let search = tasksQuery.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !search.isEmpty {
            let matchesSearch =
                context.task.title.lowercased().contains(search)
                || context.task.summary.lowercased().contains(search)
                || context.projectTitle.lowercased().contains(search)
                || context.jobTitle.lowercased().contains(search)
            if !matchesSearch { return false }
        }

        if let jobID = tasksQuery.jobID, context.jobID != jobID { return false }
        if let projectID = tasksQuery.projectID {
            guard context.projectID == projectID else { return false }
        }
        if let status = tasksQuery.status, context.task.status != status { return false }
        if let energy = tasksQuery.energy, context.task.energy != energy { return false }
        if tasksQuery.onlyNow && !context.task.isScheduledNow { return false }
        return true
    }

    private func sortTaskList(lhs: TaskContext, rhs: TaskContext) -> Bool {
        switch tasksQuery.sort {
        case .priority:
            if lhs.task.priority != rhs.task.priority { return lhs.task.priority > rhs.task.priority }
            return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
        case .title:
            return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
        case .status:
            if lhs.task.status.rawValue != rhs.task.status.rawValue { return lhs.task.status.rawValue < rhs.task.status.rawValue }
            return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
        case .project:
            let lt = lhs.projectTitle.isEmpty ? lhs.jobTitle : lhs.projectTitle
            let rt = rhs.projectTitle.isEmpty ? rhs.jobTitle : rhs.projectTitle
            if lt != rt { return lt.localizedCaseInsensitiveCompare(rt) == .orderedAscending }
            return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
        }
    }

    private func sortTasksForNow(lhs: TaskContext, rhs: TaskContext) -> Bool {
        if lhs.task.nowOrder != rhs.task.nowOrder {
            return lhs.task.nowOrder < rhs.task.nowOrder
        }
        if lhs.task.priority != rhs.task.priority { return lhs.task.priority > rhs.task.priority }
        if lhs.task.energy.maxParallelGroupSize != rhs.task.energy.maxParallelGroupSize {
            return lhs.task.energy.maxParallelGroupSize < rhs.task.energy.maxParallelGroupSize
        }
        return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
    }

    private func pauseActiveTasks(except taskID: UUID) {
        for context in taskContexts where context.task.status == .active && context.task.id != taskID {
            updateTask(taskID: context.task.id) { task in
                task.status = .paused
            }
        }
    }

    /// Deep / shallow work stays exclusive. Multitask modes can share “active” up to each task’s MT-n limit.
    private func reconcileParallelActivesForActivating(_ incoming: TaskContext) {
        if !incoming.task.energy.isMultitaskable {
            pauseActiveTasks(except: incoming.task.id)
            return
        }

        var parallel = taskContexts.filter { $0.task.status == .active && $0.task.id != incoming.task.id }
        parallel.append(incoming)

        while parallel.count > 1, !isCompatibleParallelBundle(parallel) {
            let removable = parallel.filter { $0.task.id != incoming.task.id }
            guard let victim = removable.min(by: { lhs, rhs in
                if lhs.task.priority != rhs.task.priority { return lhs.task.priority < rhs.task.priority }
                return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
            }) else { break }

            pauseTaskWithJournal(context: victim, detail: "Paused to stay within parallel limits.")
            parallel.removeAll { $0.task.id == victim.task.id }
        }
    }

    private func isCompatibleParallelBundle(_ contexts: [TaskContext]) -> Bool {
        let n = contexts.count
        guard n > 0 else { return true }
        return contexts.allSatisfy { $0.task.energy.maxParallelGroupSize >= n }
    }

    private func pauseTaskWithJournal(context: TaskContext, detail: String) {
        updateTask(taskID: context.task.id) { task in
            task.status = .paused
        }
        appendEvent(kind: .paused, context: context, detail: detail)
    }

    private func appendReflectionIfNeeded(for context: TaskContext) {
        appendEvent(
            kind: .focusRated,
            context: context,
            detail: "Focus logged.",
            focusRating: context.task.energy == .deepFocus ? 5 : 4,
            sessionMinutes: context.task.estimatedMinutes
        )

        appendEvent(
            kind: .qualityRated,
            context: context,
            detail: "Quality logged.",
            qualityRating: context.task.progress > 0.75 ? 5 : 4,
            sessionMinutes: context.task.estimatedMinutes
        )
    }

    private func appendEvent(
        kind: ActivityKind,
        context: TaskContext,
        detail: String,
        focusRating: Int? = nil,
        qualityRating: Int? = nil,
        sessionMinutes: Int? = nil
    ) {
        history.insert(
            ActivityEvent(
                timestamp: .now,
                kind: kind,
                taskID: context.task.id,
                taskTitle: context.task.title,
                projectTitle: context.projectTitle,
                detail: detail,
                focusRating: focusRating,
                qualityRating: qualityRating,
                sessionMinutes: sessionMinutes
            ),
            at: 0
        )
    }

    private func projectLocation(jobID: UUID, projectID: UUID) -> (jobIndex: Int, projectIndex: Int)? {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return nil }
        guard let projectIndex = jobs[jobIndex].projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        return (jobIndex, projectIndex)
    }

    private func taskStorageLocation(taskID: UUID) -> TaskStorageLocation? {
        if let taskIndex = standaloneTasks.firstIndex(where: { $0.id == taskID }) {
            return .standalone(taskIndex: taskIndex)
        }

        for jobIndex in jobs.indices {
            if let taskIndex = jobs[jobIndex].jobTasks.firstIndex(where: { $0.id == taskID }) {
                return .job(jobIndex: jobIndex, taskIndex: taskIndex)
            }

            for projectIndex in jobs[jobIndex].projects.indices {
                if let taskIndex = jobs[jobIndex].projects[projectIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                    return .project(jobIndex: jobIndex, projectIndex: projectIndex, taskIndex: taskIndex)
                }
            }
        }

        return nil
    }

    @discardableResult
    private func insertTask(_ task: Task, jobID: UUID?, projectID: UUID?) -> Bool {
        if let jobID {
            guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return false }

            if let projectID {
                guard let projectIndex = jobs[jobIndex].projects.firstIndex(where: { $0.id == projectID }) else {
                    return false
                }
                jobs[jobIndex].projects[projectIndex].tasks.append(task)
            } else {
                jobs[jobIndex].jobTasks.append(task)
            }
        } else {
            standaloneTasks.append(task)
        }

        derivedStateIsDirty = true
        return true
    }

    private func removeTask(at location: TaskStorageLocation) -> Task {
        let task: Task

        switch location {
        case .standalone(let taskIndex):
            task = standaloneTasks.remove(at: taskIndex)
        case .job(let jobIndex, let taskIndex):
            task = jobs[jobIndex].jobTasks.remove(at: taskIndex)
        case .project(let jobIndex, let projectIndex, let taskIndex):
            task = jobs[jobIndex].projects[projectIndex].tasks.remove(at: taskIndex)
        }

        derivedStateIsDirty = true
        return task
    }

    private func updateTask(taskID: UUID, mutate: (inout Task) -> Void) {
        if let idx = standaloneTasks.firstIndex(where: { $0.id == taskID }) {
            mutate(&standaloneTasks[idx])
            derivedStateIsDirty = true
            return
        }
        for jobIndex in jobs.indices {
            if let taskIndex = jobs[jobIndex].jobTasks.firstIndex(where: { $0.id == taskID }) {
                mutate(&jobs[jobIndex].jobTasks[taskIndex])
                derivedStateIsDirty = true
                return
            }
            for projectIndex in jobs[jobIndex].projects.indices {
                if let taskIndex = jobs[jobIndex].projects[projectIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                    mutate(&jobs[jobIndex].projects[projectIndex].tasks[taskIndex])
                    derivedStateIsDirty = true
                    return
                }
            }
        }
    }

    private func ensureDerivedState() {
        guard derivedStateIsDirty else { return }
        rebuildDerivedState()
    }

    private func rebuildDerivedState() {
        cachedJobsByID = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        cachedProjectsByID = [:]
        cachedProjectContextsByJobID = [:]
        cachedJobIndex = [:]

        cachedProjectContexts = jobs.flatMap { job in
            let projectContexts = job.projects.map { project in
                ProjectContext(
                    jobID: job.id,
                    jobTitle: job.title,
                    jobPalette: job.palette,
                    project: project
                )
            }

            cachedProjectContextsByJobID[job.id] = projectContexts
            for context in projectContexts {
                cachedProjectsByID[context.project.id] = context
            }

            let searchText = [
                job.title,
                job.summary,
                job.jobTasks.map(\.title).joined(separator: " "),
                job.projects.map(\.title).joined(separator: " "),
                job.projects.map(\.outcome).joined(separator: " "),
                job.projects.flatMap(\.tasks).map(\.title).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            let openWorkCount = job.jobTasks.filter { $0.status != .done }.count
                + job.projects.flatMap(\.tasks).filter { $0.status != .done }.count

            cachedJobIndex[job.id] = JobIndexEntry(
                searchText: searchText,
                openWorkCount: openWorkCount,
                projectCount: job.projects.count
            )

            return projectContexts
        }

        var taskContexts: [TaskContext] = standaloneTasks.map { task in
            TaskContext(
                jobID: nil,
                projectID: nil,
                jobTitle: "",
                projectTitle: "",
                jobPalette: .slate,
                task: task
            )
        }

        taskContexts.reserveCapacity(
            standaloneTasks.count
                + jobs.reduce(0) { total, job in
                    total + job.jobTasks.count + job.projects.reduce(0) { $0 + $1.tasks.count }
                }
        )

        for job in jobs {
            taskContexts.append(contentsOf: job.jobTasks.map { task in
                TaskContext(
                    jobID: job.id,
                    projectID: nil,
                    jobTitle: job.title,
                    projectTitle: "",
                    jobPalette: job.palette,
                    task: task
                )
            })

            for project in job.projects {
                taskContexts.append(contentsOf: project.tasks.map { task in
                    TaskContext(
                        jobID: job.id,
                        projectID: project.id,
                        jobTitle: job.title,
                        projectTitle: project.displayTitle,
                        jobPalette: job.palette,
                        task: task
                    )
                })
            }
        }

        cachedTaskContexts = taskContexts
        cachedTasksByID = Dictionary(uniqueKeysWithValues: taskContexts.map { ($0.task.id, $0) })

        var groupedContexts: [TaskScopeKey: [TaskContext]] = [:]
        for context in taskContexts where context.jobID != nil {
            let key = TaskScopeKey(jobID: context.jobID, projectID: context.projectID)
            groupedContexts[key, default: []].append(context)
        }
        cachedTaskContextsByScope = groupedContexts

        cachedActiveTasks = taskContexts.filter { $0.task.status == .active }
        cachedOpenTaskCount = taskContexts.filter { $0.task.status != .done }.count
        cachedCompletionCount = taskContexts.filter { $0.task.status == .done }.count
        cachedWaitingTaskCount = taskContexts.filter { $0.task.status == .waiting }.count

        let candidates = taskContexts.filter { $0.task.isScheduledNow && $0.task.isAvailableNow }
        let openNow = candidates.filter { $0.task.status != .done }.sorted(by: sortTasksForNow)
        let doneNow = candidates.filter { $0.task.status == .done }.sorted(by: sortTasksForNow)
        cachedNowTasks = openNow + doneNow
        cachedPlan = ExecutionPlanner.buildPlan(from: openNow)

        derivedStateIsDirty = false
    }

    private func makeCompatibleNowGroups(from tasks: [TaskContext]) -> [[TaskContext]] {
        var groups: [[TaskContext]] = []
        var remaining = tasks

        while let seed = remaining.first {
            let group = bestGroup(for: seed, candidates: remaining)
            let ids = Set(group.map(\.task.id))
            groups.append(group)
            remaining.removeAll { ids.contains($0.task.id) }
        }

        return groups
    }

    private func bestGroup(for seed: TaskContext, candidates: [TaskContext]) -> [TaskContext] {
        guard seed.task.energy.isMultitaskable else { return [seed] }

        var group = [seed]

        for candidate in candidates where candidate.task.id != seed.task.id {
            guard candidate.task.energy.isMultitaskable else { continue }
            let proposed = group + [candidate]
            let proposedSize = proposed.count
            let isCompatible = proposed.allSatisfy { $0.task.energy.maxParallelGroupSize >= proposedSize }
            if isCompatible {
                group.append(candidate)
            }
        }

        return group
    }

    private func orderedUnion(primary: [UUID], secondary: [UUID]) -> [UUID] {
        var result: [UUID] = []
        var seen = Set<UUID>()

        for id in primary + secondary where seen.insert(id).inserted {
            result.append(id)
        }

        return result
    }

    private func uniqueIDs(from ids: [UUID]) -> [UUID] {
        orderedUnion(primary: ids, secondary: [])
    }

    private func nextNowOrder() -> Double {
        let maxOrder = taskContexts
            .filter(\.task.isScheduledNow)
            .map(\.task.nowOrder)
            .max() ?? -1
        return maxOrder + 1
    }

    private func repeatableCompletionDetail(for task: Task) -> String {
        guard let repeatEveryMinutes = task.repeatEveryMinutes else {
            return task.cadence == .kpi ? "KPI reset." : "Repeatable reset."
        }

        if task.cadence == .kpi {
            return "KPI resets in \(repeatEveryMinutes)m."
        }

        return "Returns in \(repeatEveryMinutes)m."
    }

    private func persist() {
        schedulePersistenceIfNeeded()
    }

    func flushPersistenceNow() {
        guard persistenceEnabled else { return }
        WorkspacePersistence.saveImmediately(persistedSnapshot)
    }

    private func schedulePersistenceIfNeeded() {
        guard persistenceEnabled else { return }
        WorkspacePersistence.save(persistedSnapshot)
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var persistedSnapshot: WorkspaceSnapshot {
        let validJobIDs = Set(jobs.map(\.id))
        let validProjectIDs = Set(jobs.flatMap(\.projects).map(\.id))

        return WorkspaceSnapshot(
            jobs: jobs,
            standaloneTasks: standaloneTasks,
            history: history,
            dailyCapacityMinutes: dailyCapacityMinutes,
            tasksPresentation: tasksPresentation,
            themeMode: themeMode,
            nowPinnedJobIDs: nowPinnedJobIDs.filter { validJobIDs.contains($0) },
            nowPinnedProjectIDs: nowPinnedProjectIDs.filter { validProjectIDs.contains($0) },
            nowSuppressedJobIDs: nowSuppressedJobIDs.filter { validJobIDs.contains($0) },
            nowSuppressedProjectIDs: nowSuppressedProjectIDs.filter { validProjectIDs.contains($0) },
            focusCardDensity: focusCardDensity,
            trainingWheelsEnabled: trainingWheelsEnabled,
            typeaheadListNavigationEnabled: typeaheadListNavigationEnabled
        )
    }

    private static func bootstrapFallbackStore() -> TurboTaskStore {
        let snapshot = preview.snapshot
        return TurboTaskStore(
            jobs: snapshot.jobs,
            standaloneTasks: snapshot.standaloneTasks,
            history: snapshot.history,
            dailyCapacityMinutes: snapshot.dailyCapacityMinutes,
            themeMode: snapshot.themeMode,
            nowPinnedJobIDs: snapshot.nowPinnedJobIDs,
            nowPinnedProjectIDs: snapshot.nowPinnedProjectIDs,
            nowSuppressedJobIDs: snapshot.nowSuppressedJobIDs,
            nowSuppressedProjectIDs: snapshot.nowSuppressedProjectIDs,
            focusCardDensity: snapshot.focusCardDensity,
            trainingWheelsEnabled: snapshot.trainingWheelsEnabled,
            typeaheadListNavigationEnabled: snapshot.typeaheadListNavigationEnabled,
            tasksPresentation: snapshot.tasksPresentation,
            persistenceEnabled: true
        )
    }

    private static func emptyWorkspaceStore() -> TurboTaskStore {
        TurboTaskStore(
            jobs: [],
            standaloneTasks: [],
            history: [],
            dailyCapacityMinutes: 540,
            persistenceEnabled: true
        )
    }

}

struct ActivitySummary: Identifiable {
    let date: Date
    let completions: Int
    let focusAverage: Double

    var id: Date { date }
}

extension TurboTaskStore {
    static let preview: TurboTaskStore = {
        let now = Date.now
        let jobs = [
            Job(
                title: "Stackfuse",
                summary: "AI go-to-market systems.",
                palette: .forest,
                projects: [
                    Project(
                        title: "Outreach System",
                        outcome: "Stabilize outbound operations.",
                        tasks: [
                            Task(
                                title: "Draft scoring rubric",
                                summary: "Define lead scoring.",
                                why: "Sharper triage makes the queue usable.",
                                energy: .deepFocus,
                                status: .queued,
                                progress: 0.35,
                                estimatedMinutes: 90,
                                isScheduledNow: true,
                                priority: 5,
                                nextStep: "Write factors before prompts."
                            ),
                            Task(
                                title: "Review agent failures",
                                summary: "Classify the last failed runs.",
                                why: "Noise has to be removed before more automation.",
                                energy: .shallowWork,
                                status: .queued,
                                progress: 0.10,
                                estimatedMinutes: 35,
                                isScheduledNow: true,
                                priority: 4,
                                nextStep: "Tag each failure."
                            ),
                            Task(
                                title: "Reconnect Clay importer",
                                summary: "Map the export fields once the run lands.",
                                why: "This operator loop should stay visible while the export settles.",
                                energy: .multitask2,
                                status: .active,
                                progress: 0.25,
                                estimatedMinutes: 20,
                                isScheduledNow: true,
                                priority: 4,
                                nextStep: "Validate the final field mapping."
                            ),
                            Task(
                                title: "Wait for Clay export",
                                summary: "Reconnect fields after export.",
                                why: "No babysitting while it runs.",
                                energy: .multitask3,
                                status: .waiting,
                                progress: 0.55,
                                estimatedMinutes: 10,
                                isScheduledNow: true,
                                priority: 3,
                                waitingOn: "Export still processing.",
                                nextStep: "Validate import fields."
                            )
                        ],
                        iconEmoji: "📣"
                    ),
                    Project(
                        title: "Agent Monitoring",
                        outcome: "Make agent states readable.",
                        tasks: [
                            Task(
                                title: "Design state chips",
                                summary: "Map run states into one UI language.",
                                why: "Waiting time is only useful if signals are clear.",
                                energy: .shallowWork,
                                status: .paused,
                                progress: 0.25,
                                estimatedMinutes: 45,
                                isScheduledNow: false,
                                priority: 3,
                                nextStep: "Separate blocked and healthy."
                            )
                        ],
                        iconEmoji: "🤖"
                    )
                ]
            ),
            Job(
                title: "Rendframe",
                summary: "Product studio work.",
                palette: .amber,
                projects: [
                    Project(
                        title: "Landing Refresh",
                        outcome: "Tighten story and hierarchy.",
                        tasks: [
                            Task(
                                title: "Rewrite hero hierarchy",
                                summary: "Clarify the promise.",
                                why: "The page has to explain itself immediately.",
                                energy: .deepFocus,
                                cadence: .kpi,
                                status: .queued,
                                progress: 0.05,
                                estimatedMinutes: 75,
                                isScheduledNow: true,
                                priority: 4,
                                nextStep: "Sharpen the headline.",
                                repeatEveryMinutes: 60,
                                kpiTarget: 10,
                                kpiUnit: "outreaches"
                            )
                        ],
                        iconEmoji: "✨"
                    )
                ]
            ),
            Job(
                title: "Personal Admin",
                summary: "Necessary background work.",
                palette: .slate,
                projects: [
                    Project(
                        title: "Finance Ops",
                        outcome: "Close mental drag.",
                        tasks: [
                            Task(
                                title: "Send missing invoices",
                                summary: "Package receipts and reply.",
                                why: "Open admin loops keep leaking attention.",
                                energy: .shallowWork,
                                cadence: .repeatable,
                                status: .queued,
                                progress: 0,
                                estimatedMinutes: 25,
                                isScheduledNow: true,
                                priority: 2,
                                nextStep: "Collect the missing PDFs.",
                                repeatEveryMinutes: 1440
                            ),
                            Task(
                                title: "Renew business insurance",
                                summary: "Finish the policy renewal.",
                                why: "Necessary but not morning work.",
                                energy: .shallowWork,
                                status: .done,
                                progress: 1,
                                estimatedMinutes: 15,
                                isScheduledNow: false,
                                priority: 1,
                                nextStep: "Archive the document."
                            )
                        ],
                        iconEmoji: "💰"
                    )
                ]
            )
        ]

        let history = [
            ActivityEvent(
                timestamp: now.addingTimeInterval(-900),
                kind: .started,
                taskID: jobs[0].projects[0].tasks[2].id,
                taskTitle: jobs[0].projects[0].tasks[2].title,
                projectTitle: jobs[0].projects[0].title,
                detail: "Morning focus block started.",
                sessionMinutes: 45
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-2400),
                kind: .completed,
                taskID: jobs[2].projects[0].tasks[1].id,
                taskTitle: jobs[2].projects[0].tasks[1].title,
                projectTitle: jobs[2].projects[0].title,
                detail: "Completed.",
                qualityRating: 4,
                sessionMinutes: 15
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-2700),
                kind: .focusRated,
                taskID: jobs[2].projects[0].tasks[1].id,
                taskTitle: jobs[2].projects[0].tasks[1].title,
                projectTitle: jobs[2].projects[0].title,
                detail: "Contained block.",
                focusRating: 4,
                sessionMinutes: 15
            )
        ]

        let store = TurboTaskStore(
            jobs: jobs,
            standaloneTasks: [],
            history: history,
            dailyCapacityMinutes: 540,
            persistenceEnabled: false
        )
        store.selection = .task(
            jobID: jobs[0].id,
            projectID: jobs[0].projects[0].id,
            taskID: jobs[0].projects[0].tasks[2].id
        )
        return store
    }()
}
