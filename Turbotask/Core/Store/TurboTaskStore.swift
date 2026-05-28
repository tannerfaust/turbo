//
//  TurboTaskStore.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
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
        case battery
        case archive
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
            case .battery:
                "Battery"
            case .archive:
                "Archive"
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
            case .battery:
                "battery.100percent"
            case .archive:
                "archivebox"
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
        case setListGrouping(NowListGroupingMode)
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
        case manual
        case priority
        case title
        case status
        case project

        var id: String { rawValue }

        var title: String {
            switch self {
            case .manual:
                "Manual"
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
        /// When false, the task registry hides archived tasks unless the user enables “Show archived”.
        var includeArchivedTasks = false
        var sort: TaskSortOption = .manual
    }

    @Published var selectedScreen: Screen = .now {
        didSet {
            guard oldValue != selectedScreen else { return }
            scheduleNowRowFlashSync()
        }
    }
    @Published var jobs: [Job] {
        didSet {
            derivedStateIsDirty = true
            if !suppressDidSetPersistence {
                schedulePersistenceIfNeeded()
            }
        }
    }

    @Published var standaloneTasks: [Task] {
        didSet {
            derivedStateIsDirty = true
            if !suppressDidSetPersistence {
                schedulePersistenceIfNeeded()
            }
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
    @Published var dayBatteryStartMinutes: Int {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var dayBatteryEndMinutes: Int {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var dayBatteryShowsPercentageInMenuBar: Bool {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var dayBatteryUsesWideMenuBarItem: Bool {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    /// 0 = disabled. Archive incomplete, non-active tasks after this many hours without an activity log entry.
    @Published var taskAutoArchiveAfterIdleHours: Int {
        didSet {
            if persistenceEnabled, oldValue != taskAutoArchiveAfterIdleHours {
                schedulePersistenceIfNeeded()
            }
        }
    }
    /// 0 = off. Archive **done** tasks after this many days from the last completion event in the activity log.
    @Published var doneTaskAutoArchiveAfterDays: Int {
        didSet {
            if persistenceEnabled, oldValue != doneTaskAutoArchiveAfterDays {
                schedulePersistenceIfNeeded()
            }
        }
    }
    /// 0 = never. Permanently remove archived tasks after this many days in archive (see `Task.archivedAt`).
    @Published var archivedTaskPurgeAfterDays: Int {
        didSet {
            if persistenceEnabled, oldValue != archivedTaskPurgeAfterDays {
                schedulePersistenceIfNeeded()
            }
        }
    }
    @Published var themeMode: AppThemeMode {
        didSet {
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowPinnedJobIDs: [UUID] {
        didSet {
            derivedStateIsDirty = true
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowPinnedProjectIDs: [UUID] {
        didSet {
            derivedStateIsDirty = true
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowSuppressedJobIDs: [UUID] {
        didSet {
            derivedStateIsDirty = true
            schedulePersistenceIfNeeded()
        }
    }
    @Published var nowSuppressedProjectIDs: [UUID] {
        didSet {
            derivedStateIsDirty = true
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
    @Published var newNowTaskPlacement: NewNowTaskPlacement {
        didSet {
            if persistenceEnabled, oldValue != newNowTaskPlacement {
                schedulePersistenceIfNeeded()
            }
        }
    }
    @Published var focusOverlayPresenceMode: FocusOverlayPresenceMode {
        didSet {
            if persistenceEnabled, oldValue != focusOverlayPresenceMode {
                schedulePersistenceIfNeeded()
            }
            if isFocusOverlayVisible {
                FocusOverlayController.shared.applyPresenceMode(focusOverlayPresenceMode)
            }
        }
    }
    /// Last known focus card window frame; restored on show and after relaunch.
    @Published var focusOverlayWindowFrame: FocusOverlayWindowFrame? {
        didSet {
            if persistenceEnabled, oldValue != focusOverlayWindowFrame {
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
    /// Shown when starting a task would exceed compatible parallel in-progress work; user can upgrade all to MT-n or switch only.
    @Published var multitaskUpgradeOffer: MultitaskUpgradeOffer?
    /// Shown when more than four tasks would be active together (hard limit).
    @Published var parallelActiveLimitMessage: String?

    let appUndoManager = UndoManager()

    private let persistenceEnabled: Bool
    private let calendar = Calendar(identifier: .iso8601)
    private var derivedStateIsDirty = true
    private var lastIdleAutoArchiveAt: Date?
    private var lastDoneAutoArchiveAt: Date?
    private var lastArchivedPurgeAt: Date?
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
    private var cachedVisibleNowJobIDs: [UUID] = []
    private var cachedVisibleNowProjectIDs: [UUID] = []
    private var cachedScopedNowTasks: [TaskContext] = []
    private var cachedNowTreeGroups: [[TaskContext]] = []
    /// Cached today metrics — rebuilt with derived state.
    private var cachedWorkedMinutesToday: Int = 0
    private var cachedFocusRatingAverage: Double = 0
    private var cachedQualityRatingAverage: Double = 0
    /// When true, `jobs`/`standaloneTasks` didSet won't schedule persistence (callers do it explicitly).
    private var suppressDidSetPersistence = false
    /// Maximum history events to retain. Oldest non-metric events are pruned beyond this.
    private static let historyEventCap = 10_000

    init(
        jobs: [Job],
        standaloneTasks: [Task] = [],
        history: [ActivityEvent],
        dailyCapacityMinutes: Int = 540,
        dayBatteryStartMinutes: Int = 8 * 60,
        dayBatteryEndMinutes: Int = 0,
        dayBatteryShowsPercentageInMenuBar: Bool = true,
        dayBatteryUsesWideMenuBarItem: Bool = false,
        taskAutoArchiveAfterIdleHours: Int = 0,
        doneTaskAutoArchiveAfterDays: Int = 0,
        archivedTaskPurgeAfterDays: Int = 0,
        themeMode: AppThemeMode = .system,
        nowPinnedJobIDs: [UUID] = [],
        nowPinnedProjectIDs: [UUID] = [],
        nowSuppressedJobIDs: [UUID] = [],
        nowSuppressedProjectIDs: [UUID] = [],
        focusCardDensity: FocusCardDensity = .standard,
        newNowTaskPlacement: NewNowTaskPlacement = .bottom,
        focusOverlayPresenceMode: FocusOverlayPresenceMode = .allDesktops,
        focusOverlayWindowFrame: FocusOverlayWindowFrame? = nil,
        trainingWheelsEnabled: Bool = true,
        typeaheadListNavigationEnabled: Bool = true,
        tasksPresentation: TasksPresentationState? = nil,
        persistenceEnabled: Bool = true
    ) {
        self.jobs = jobs
        self.standaloneTasks = standaloneTasks
        self.history = history.sorted(by: { $0.timestamp > $1.timestamp })
        self.dailyCapacityMinutes = dailyCapacityMinutes
        self.dayBatteryStartMinutes = dayBatteryStartMinutes
        self.dayBatteryEndMinutes = dayBatteryEndMinutes
        self.dayBatteryShowsPercentageInMenuBar = dayBatteryShowsPercentageInMenuBar
        self.dayBatteryUsesWideMenuBarItem = dayBatteryUsesWideMenuBarItem
        self.taskAutoArchiveAfterIdleHours = taskAutoArchiveAfterIdleHours
        self.doneTaskAutoArchiveAfterDays = doneTaskAutoArchiveAfterDays
        self.archivedTaskPurgeAfterDays = archivedTaskPurgeAfterDays
        self.themeMode = themeMode
        self.nowPinnedJobIDs = nowPinnedJobIDs
        self.nowPinnedProjectIDs = nowPinnedProjectIDs
        self.nowSuppressedJobIDs = nowSuppressedJobIDs
        self.nowSuppressedProjectIDs = nowSuppressedProjectIDs
        self.focusCardDensity = focusCardDensity
        self.newNowTaskPlacement = newNowTaskPlacement
        self.focusOverlayPresenceMode = focusOverlayPresenceMode
        self.focusOverlayWindowFrame = focusOverlayWindowFrame
        self.trainingWheelsEnabled = trainingWheelsEnabled
        self.typeaheadListNavigationEnabled = typeaheadListNavigationEnabled
        self.tasksPresentation = tasksPresentation ?? TasksPresentationState()
        self.persistenceEnabled = persistenceEnabled
        rebuildDerivedState()
        migrateArchivedTimestampsIfNeeded()
    }

    static func bootstrap() -> TurboTaskStore {
        switch WorkspacePersistence.loadOutcome() {
        case .loaded(let snapshot), .recoveredFromBackup(let snapshot):
            let store = TurboTaskStore(
                jobs: snapshot.jobs,
                standaloneTasks: snapshot.standaloneTasks,
                history: snapshot.history,
                dailyCapacityMinutes: snapshot.dailyCapacityMinutes,
                dayBatteryStartMinutes: snapshot.dayBatteryStartMinutes,
                dayBatteryEndMinutes: snapshot.dayBatteryEndMinutes,
                dayBatteryShowsPercentageInMenuBar: snapshot.dayBatteryShowsPercentageInMenuBar,
                dayBatteryUsesWideMenuBarItem: snapshot.dayBatteryUsesWideMenuBarItem,
                taskAutoArchiveAfterIdleHours: snapshot.taskAutoArchiveAfterIdleHours,
                doneTaskAutoArchiveAfterDays: snapshot.doneTaskAutoArchiveAfterDays,
                archivedTaskPurgeAfterDays: snapshot.archivedTaskPurgeAfterDays,
                themeMode: snapshot.themeMode,
                nowPinnedJobIDs: snapshot.nowPinnedJobIDs,
                nowPinnedProjectIDs: snapshot.nowPinnedProjectIDs,
                nowSuppressedJobIDs: snapshot.nowSuppressedJobIDs,
                nowSuppressedProjectIDs: snapshot.nowSuppressedProjectIDs,
                focusCardDensity: snapshot.focusCardDensity,
                newNowTaskPlacement: snapshot.newNowTaskPlacement,
                focusOverlayPresenceMode: snapshot.focusOverlayPresenceMode,
                focusOverlayWindowFrame: snapshot.focusOverlayWindowFrame,
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
            dayBatteryStartMinutes: dayBatteryStartMinutes,
            dayBatteryEndMinutes: dayBatteryEndMinutes,
            dayBatteryShowsPercentageInMenuBar: dayBatteryShowsPercentageInMenuBar,
            dayBatteryUsesWideMenuBarItem: dayBatteryUsesWideMenuBarItem,
            taskAutoArchiveAfterIdleHours: taskAutoArchiveAfterIdleHours,
            doneTaskAutoArchiveAfterDays: doneTaskAutoArchiveAfterDays,
            archivedTaskPurgeAfterDays: archivedTaskPurgeAfterDays,
            tasksPresentation: tasksPresentation,
            themeMode: themeMode,
            nowPinnedJobIDs: nowPinnedJobIDs,
            nowPinnedProjectIDs: nowPinnedProjectIDs,
            nowSuppressedJobIDs: nowSuppressedJobIDs,
            nowSuppressedProjectIDs: nowSuppressedProjectIDs,
            focusCardDensity: focusCardDensity,
            newNowTaskPlacement: newNowTaskPlacement,
            focusOverlayPresenceMode: focusOverlayPresenceMode,
            focusOverlayWindowFrame: focusOverlayWindowFrame,
            trainingWheelsEnabled: trainingWheelsEnabled,
            typeaheadListNavigationEnabled: typeaheadListNavigationEnabled
        )
    }

    /// Called by `FocusOverlayController` when the panel moves or resizes (debounced there).
    func recordFocusOverlayWindowFrame(_ rect: NSRect) {
        let next = FocusOverlayWindowFrame(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
        guard focusOverlayWindowFrame != next else { return }
        focusOverlayWindowFrame = next
    }

    var taskContexts: [TaskContext] {
        ensureDerivedState()
        return cachedTaskContexts
    }

    /// Archived tasks only, most recently archived first (completion time as fallback when `archivedAt` is nil).
    var archivedTaskContexts: [TaskContext] {
        ensureDerivedState()
        func sortKey(_ ctx: TaskContext) -> Date {
            ctx.task.archivedAt ?? latestCompletionTimestamp(for: ctx.task.id) ?? .distantPast
        }
        return cachedTaskContexts
            .filter(\.task.isArchived)
            .sorted { sortKey($0) > sortKey($1) }
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
        ensureDerivedState()
        return cachedFocusRatingAverage
    }

    var qualityRatingAverage: Double {
        ensureDerivedState()
        return cachedQualityRatingAverage
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
            .filter { context in
                if !tasksQuery.includeArchivedTasks, context.task.isArchived { return false }
                return matchesTaskQuery(context)
            }
            .sorted(by: sortTaskList)
    }

    var visibleTaskFieldsInDisplayOrder: [TaskVisibleField] {
        TaskVisibleField.allCases.filter { tasksPresentation.visibleFields.contains($0) }
    }

    var filteredTaskContextsByStatus: [(status: TaskStatus, contexts: [TaskContext])] {
        var buckets: [TaskStatus: [TaskContext]] = [:]
        for ctx in filteredTaskContexts {
            buckets[ctx.task.status, default: []].append(ctx)
        }
        return TaskStatus.allCases.map { status in
            (status: status, contexts: buckets[status] ?? [])
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
        let raw = cachedTaskContextsByScope[TaskScopeKey(jobID: jobID, projectID: projectID)] ?? []
        return raw.filter { !$0.task.isArchived }
    }

    func jobLevelTaskContexts(jobID: UUID) -> [TaskContext] {
        ensureDerivedState()
        let raw = cachedTaskContextsByScope[TaskScopeKey(jobID: jobID, projectID: nil)] ?? []
        return raw.filter { !$0.task.isArchived }
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
            selection = nowSelection(for: activeTask)
            return
        }

        if let firstNowTask = nowTasks.first(where: { $0.task.status != .done }) {
            selection = nowSelection(for: firstNowTask)
            return
        }

        if let firstJob = jobs.first {
            selection = .job(firstJob.id)
        }
    }

    func select(_ selection: Selection?) {
        guard self.selection != selection else { return }
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
            select(nowSelection(for: first))
            return
        } else {
            return
        }

        let next = index + step
        guard tasks.indices.contains(next) else { return }
        let ctx = tasks[next]
        select(nowSelection(for: ctx))
    }

    private func nowSelection(for context: TaskContext) -> Selection {
        .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private func preferredNowSelectionAfterCompleting(_ context: TaskContext) -> Selection? {
        let ordered = scopedNowTasks
        guard let index = ordered.firstIndex(where: {
            $0.task.id == context.task.id && $0.jobID == context.jobID && $0.projectID == context.projectID
        }) else {
            return nil
        }

        let forward = Array(ordered.dropFirst(index + 1))
        let backward = Array(ordered.prefix(index).reversed())

        if let nextOpen = forward.first(where: { $0.task.status != .done }) {
            return nowSelection(for: nextOpen)
        }
        if let previousOpen = backward.first(where: { $0.task.status != .done }) {
            return nowSelection(for: previousOpen)
        }
        if let nextVisible = forward.first {
            return nowSelection(for: nextVisible)
        }
        if let previousVisible = backward.first {
            return nowSelection(for: previousVisible)
        }
        return nil
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

        presentComposer(
            ComposerContext(
            kind: kind,
            preferredJobID: preferredJobID,
            preferredProjectID: preferredProjectID,
            scheduleForNow: scheduleForNow
            )
        )
    }

    private func presentComposer(_ context: ComposerContext) {
        DispatchQueue.main.async { [weak self] in
            self?.composer = context
        }
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
        registerUndoAddJob(jobID: job.id)
    }

    private func registerUndoAddJob(jobID: UUID) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                let job = self.jobs[idx]
                self.jobs.remove(at: idx)
                if self.selectedJobID == jobID {
                    self.selection = nil
                    self.ensureSelection()
                }
                self.persist()


                self.appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.jobs.append(job)
                        self.selection = .job(job.id)
                        self.persist()
                        self.registerUndoAddJob(jobID: job.id)
                    }
                }
                self.appUndoManager.setActionName("Add Job")
            }
        }
        appUndoManager.setActionName("Add Job")
    }

    func addProject(title: String, outcome: String, iconEmoji: String, jobID: UUID) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let project = Project(title: title, outcome: outcome, tasks: [], iconEmoji: iconEmoji)
        jobs[jobIndex].projects.append(project)
        selection = .project(jobID: jobID, projectID: project.id)
        persist()
        registerUndoAddProject(projectID: project.id, jobID: jobID)
    }

    private func registerUndoAddProject(projectID: UUID, jobID: UUID) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.deleteProject(jobID: jobID, projectID: projectID)
            }
        }
        appUndoManager.setActionName("Add Project")
    }

    func openNewProject(preferredJobID: UUID?) {
        presentComposer(
            ComposerContext(
                kind: .project,
                preferredJobID: preferredJobID,
                preferredProjectID: nil,
                scheduleForNow: false
            )
        )
    }

    func addTask(
        title: String,
        status: TaskStatus,
        energy: TaskEnergy,
        cadence: TaskCadence,
        isScheduledNow: Bool,
        repeatEveryMinutes: Int?,
        kpiTarget: Int?,
        kpiRoundsRemaining: Int?,
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
            nowOrder: initialNowOrderForNewTask(isScheduledNow: isScheduledNow),
            priority: 3,
            waitingOn: nil,
            nextStep: "",
            repeatEveryMinutes: cadence == .repeatable || (cadence == .kpi && kpiRoundsRemaining != nil) ? repeatEveryMinutes : nil,
            kpiTarget: cadence == .kpi ? kpiTarget : nil,
            kpiUnit: nil,
            kpiRoundsRemaining: cadence == .kpi ? kpiRoundsRemaining : nil,
            kpiCount: 0,
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
        registerUndoAddTask(taskID: task.id)
    }

    private func registerUndoAddTask(taskID: UUID) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let ctx = self.taskContext(taskID: taskID) else { return }
                self.deleteTask(context: ctx)
            }
        }
        appUndoManager.setActionName("Add Task")
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

        let snapshotBefore = context.task
        let nowOrdersBefore = captureNowOrdersForUndo()
        let sourceJobID = context.jobID
        let sourceProjectID = context.projectID

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
            registerUndoTaskEdit(
                taskID: snapshotBefore.id,
                snapshotBefore: snapshotBefore,
                nowOrdersBefore: nowOrdersBefore,
                sourceJobID: sourceJobID,
                sourceProjectID: sourceProjectID,
                destinationChanged: true
            )
            return true
        }

        updateTask(taskID: context.task.id, mutate: mutate)
        selection = .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
        persist()
        registerUndoTaskEdit(
            taskID: snapshotBefore.id,
            snapshotBefore: snapshotBefore,
            nowOrdersBefore: nowOrdersBefore,
            sourceJobID: sourceJobID,
            sourceProjectID: sourceProjectID,
            destinationChanged: false
        )
        return true
    }

    private func registerUndoTaskEdit(
        taskID: UUID,
        snapshotBefore: Task,
        nowOrdersBefore: [UUID: Double],
        sourceJobID: UUID?,
        sourceProjectID: UUID?,
        destinationChanged: Bool
    ) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let ctx = self.taskContext(taskID: taskID) else { return }
                let redoSnapshot = ctx.task
                let redoOrders = self.captureNowOrdersForUndo()
                let redoJobID = ctx.jobID
                let redoProjectID = ctx.projectID

                if destinationChanged {
                    guard let loc = self.taskStorageLocation(taskID: taskID) else { return }
                    var task = self.removeTask(at: loc)
                    task.applyFullState(from: snapshotBefore)
                    _ = self.insertTask(task, jobID: sourceJobID, projectID: sourceProjectID)
                    self.selection = .task(jobID: sourceJobID, projectID: sourceProjectID, taskID: taskID)
                } else {
                    self.restoreTaskSnapshot(snapshotBefore)
                    self.selection = .task(jobID: sourceJobID, projectID: sourceProjectID, taskID: taskID)
                }
                self.applyNowOrders(nowOrdersBefore)
                self.derivedStateIsDirty = true
                self.persist()

                self.registerUndoTaskEdit(
                    taskID: taskID,
                    snapshotBefore: redoSnapshot,
                    nowOrdersBefore: redoOrders,
                    sourceJobID: redoJobID,
                    sourceProjectID: redoProjectID,
                    destinationChanged: destinationChanged
                )
            }
        }
        appUndoManager.setActionName("Edit Task")
    }

    /// Selects this task in the single selection model (Now focus, row highlight, etc.).
    func selectTask(_ context: TaskContext) {
        select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
    }

    private struct DeleteTaskUndoPayload {
        var task: Task
        var jobID: UUID?
        var projectID: UUID?
        var historyEvents: [ActivityEvent]
        var restoreSelection: Bool
    }

    func deleteTask(context: TaskContext) {
        guard let payload = makeDeleteTaskPayload(removing: context) else { return }
        applyDeleteTaskPayload(payload)
        persist()
        registerUndoRestoreDeletedTask(payload)
    }

    /// Removes the task and related history from the store (no undo, no persist).
    private func applyDeleteTaskPayload(_ payload: DeleteTaskUndoPayload) {
        let tid = payload.task.id

        if let sIdx = standaloneTasks.firstIndex(where: { $0.id == tid }) {
            standaloneTasks.remove(at: sIdx)
        } else if let jid = payload.jobID, let jidx = jobs.firstIndex(where: { $0.id == jid }) {
            if let tidx = jobs[jidx].jobTasks.firstIndex(where: { $0.id == tid }) {
                jobs[jidx].jobTasks.remove(at: tidx)
            } else if let pid = payload.projectID,
                      let pidx = jobs[jidx].projects.firstIndex(where: { $0.id == pid }),
                      let tidx = jobs[jidx].projects[pidx].tasks.firstIndex(where: { $0.id == tid }) {
                jobs[jidx].projects[pidx].tasks.remove(at: tidx)
            } else {
                return
            }
        }

        scrubHistoryPreservingMetrics(removingTaskID: tid)
        if payload.restoreSelection {
            selection = nil
            ensureSelection()
        }
    }

    private func makeDeleteTaskPayload(removing context: TaskContext) -> DeleteTaskUndoPayload? {
        let tid = context.task.id
        guard taskStorageLocation(taskID: tid) != nil else { return nil }

        let historyEvents = history.filter { $0.taskID == tid }
        let restoreSelection: Bool = {
            if case .task(_, _, let selectedID) = selection { return selectedID == tid }
            return false
        }()

        return DeleteTaskUndoPayload(
            task: context.task,
            jobID: context.jobID,
            projectID: context.projectID,
            historyEvents: historyEvents,
            restoreSelection: restoreSelection
        )
    }

    private func registerUndoRestoreDeletedTask(_ payload: DeleteTaskUndoPayload) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreDeletedTask(payload)
            }
        }
        appUndoManager.setActionName("Delete Task")
    }

    private func restoreDeletedTask(_ payload: DeleteTaskUndoPayload) {
        _ = insertTask(payload.task, jobID: payload.jobID, projectID: payload.projectID)
        if !payload.historyEvents.isEmpty {
            history.append(contentsOf: payload.historyEvents)
            history.sort { $0.timestamp > $1.timestamp }
        }
        if payload.restoreSelection {
            selection = .task(jobID: payload.jobID, projectID: payload.projectID, taskID: payload.task.id)
        }
        derivedStateIsDirty = true
        persist()


        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                self?.redoDeleteAfterRestore(taskID: payload.task.id)
            }
        }
        appUndoManager.setActionName("Restore Task")
    }

    private func redoDeleteAfterRestore(taskID: UUID) {
        guard let ctx = taskContext(taskID: taskID),
              let payload = makeDeleteTaskPayload(removing: ctx) else { return }
        applyDeleteTaskPayload(payload)
        persist()


        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreDeletedTask(payload)
            }
        }
        appUndoManager.setActionName("Delete Task")
    }

    func moveJobs(fromOffsets source: IndexSet, toOffset destination: Int) {
        let savedJobs = jobs
        jobs.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
        registerUndoJobReorder(savedJobs: savedJobs)
    }

    private func registerUndoJobReorder(savedJobs: [Job]) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let redo = self.jobs
                self.jobs = savedJobs
                self.derivedStateIsDirty = true
                self.persist()
                self.registerUndoJobReorder(savedJobs: redo)
            }
        }
        appUndoManager.setActionName("Move Job")
    }

    func moveProjects(jobID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let savedProjects = jobs[jobIndex].projects
        jobs[jobIndex].projects.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectReorder(jobID: jobID, savedProjects: savedProjects)
    }

    private func registerUndoProjectReorder(jobID: UUID, savedProjects: [Project]) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self,
                      let jobIdx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                let redo = self.jobs[jobIdx].projects
                self.jobs[jobIdx].projects = savedProjects
                self.derivedStateIsDirty = true
                self.persist()
                self.registerUndoProjectReorder(jobID: jobID, savedProjects: redo)
            }
        }
        appUndoManager.setActionName("Move Project")
    }

    func moveJobTasks(jobID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let saved = jobs[jobIndex].jobTasks
        jobs[jobIndex].jobTasks.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
        registerUndoJobTaskReorder(jobID: jobID, saved: saved)
    }

    private func registerUndoJobTaskReorder(jobID: UUID, saved: [Task]) {
        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self,
                      let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                let redo = self.jobs[idx].jobTasks
                self.jobs[idx].jobTasks = saved
                self.derivedStateIsDirty = true
                self.persist()
                self.registerUndoJobTaskReorder(jobID: jobID, saved: redo)
            }
        }
        appUndoManager.setActionName("Move Task")
    }

    func moveProjectTasks(jobID: UUID, projectID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }),
              let projIndex = jobs[jobIndex].projects.firstIndex(where: { $0.id == projectID }) else { return }
        let saved = jobs[jobIndex].projects[projIndex].tasks
        jobs[jobIndex].projects[projIndex].tasks.move(fromOffsets: source, toOffset: destination)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectTaskReorder(jobID: jobID, projectID: projectID, saved: saved)
    }

    private func registerUndoProjectTaskReorder(jobID: UUID, projectID: UUID, saved: [Task]) {
        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self,
                      let jIdx = self.jobs.firstIndex(where: { $0.id == jobID }),
                      let pIdx = self.jobs[jIdx].projects.firstIndex(where: { $0.id == projectID }) else { return }
                let redo = self.jobs[jIdx].projects[pIdx].tasks
                self.jobs[jIdx].projects[pIdx].tasks = saved
                self.derivedStateIsDirty = true
                self.persist()
                self.registerUndoProjectTaskReorder(jobID: jobID, projectID: projectID, saved: redo)
            }
        }
        appUndoManager.setActionName("Move Task")
    }

    // MARK: - ID-based reorder (drag-and-drop)

    func reorderJob(_ movingID: UUID, before targetID: UUID) {
        guard movingID != targetID else { return }
        guard let srcIdx = jobs.firstIndex(where: { $0.id == movingID }),
              let dstIdx = jobs.firstIndex(where: { $0.id == targetID }) else { return }
        let saved = jobs
        let item = jobs.remove(at: srcIdx)
        let insertIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        jobs.insert(item, at: insertIdx)
        derivedStateIsDirty = true
        persist()
        registerUndoJobReorder(savedJobs: saved)
    }

    func reorderJobToEnd(_ movingID: UUID) {
        guard let srcIdx = jobs.firstIndex(where: { $0.id == movingID }),
              srcIdx < jobs.count - 1 else { return }
        let saved = jobs
        let item = jobs.remove(at: srcIdx)
        jobs.append(item)
        derivedStateIsDirty = true
        persist()
        registerUndoJobReorder(savedJobs: saved)
    }

    func reorderJobTask(_ jobID: UUID, movingTaskID: UUID, before targetTaskID: UUID) {
        guard movingTaskID != targetTaskID,
              let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let srcIdx = jobs[jIdx].jobTasks.firstIndex(where: { $0.id == movingTaskID }),
              let dstIdx = jobs[jIdx].jobTasks.firstIndex(where: { $0.id == targetTaskID }) else { return }
        let saved = jobs[jIdx].jobTasks
        let item = jobs[jIdx].jobTasks.remove(at: srcIdx)
        let insertIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        jobs[jIdx].jobTasks.insert(item, at: insertIdx)
        derivedStateIsDirty = true
        persist()
        registerUndoJobTaskReorder(jobID: jobID, saved: saved)
    }

    func reorderJobTaskToEnd(_ jobID: UUID, movingTaskID: UUID) {
        guard let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let srcIdx = jobs[jIdx].jobTasks.firstIndex(where: { $0.id == movingTaskID }),
              srcIdx < jobs[jIdx].jobTasks.count - 1 else { return }
        let saved = jobs[jIdx].jobTasks
        let item = jobs[jIdx].jobTasks.remove(at: srcIdx)
        jobs[jIdx].jobTasks.append(item)
        derivedStateIsDirty = true
        persist()
        registerUndoJobTaskReorder(jobID: jobID, saved: saved)
    }

    func reorderProject(_ jobID: UUID, movingProjectID: UUID, before targetProjectID: UUID) {
        guard movingProjectID != targetProjectID,
              let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let srcIdx = jobs[jIdx].projects.firstIndex(where: { $0.id == movingProjectID }),
              let dstIdx = jobs[jIdx].projects.firstIndex(where: { $0.id == targetProjectID }) else { return }
        let saved = jobs[jIdx].projects
        let item = jobs[jIdx].projects.remove(at: srcIdx)
        let insertIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        jobs[jIdx].projects.insert(item, at: insertIdx)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectReorder(jobID: jobID, savedProjects: saved)
    }

    func reorderProjectToEnd(_ jobID: UUID, movingProjectID: UUID) {
        guard let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let srcIdx = jobs[jIdx].projects.firstIndex(where: { $0.id == movingProjectID }),
              srcIdx < jobs[jIdx].projects.count - 1 else { return }
        let saved = jobs[jIdx].projects
        let item = jobs[jIdx].projects.remove(at: srcIdx)
        jobs[jIdx].projects.append(item)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectReorder(jobID: jobID, savedProjects: saved)
    }

    func reorderProjectTask(_ jobID: UUID, projectID: UUID, movingTaskID: UUID, before targetTaskID: UUID) {
        guard movingTaskID != targetTaskID,
              let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let pIdx = jobs[jIdx].projects.firstIndex(where: { $0.id == projectID }),
              let srcIdx = jobs[jIdx].projects[pIdx].tasks.firstIndex(where: { $0.id == movingTaskID }),
              let dstIdx = jobs[jIdx].projects[pIdx].tasks.firstIndex(where: { $0.id == targetTaskID }) else { return }
        let saved = jobs[jIdx].projects[pIdx].tasks
        let item = jobs[jIdx].projects[pIdx].tasks.remove(at: srcIdx)
        let insertIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        jobs[jIdx].projects[pIdx].tasks.insert(item, at: insertIdx)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectTaskReorder(jobID: jobID, projectID: projectID, saved: saved)
    }

    func reorderProjectTaskToEnd(_ jobID: UUID, projectID: UUID, movingTaskID: UUID) {
        guard let jIdx = jobs.firstIndex(where: { $0.id == jobID }),
              let pIdx = jobs[jIdx].projects.firstIndex(where: { $0.id == projectID }),
              let srcIdx = jobs[jIdx].projects[pIdx].tasks.firstIndex(where: { $0.id == movingTaskID }),
              srcIdx < jobs[jIdx].projects[pIdx].tasks.count - 1 else { return }
        let saved = jobs[jIdx].projects[pIdx].tasks
        let item = jobs[jIdx].projects[pIdx].tasks.remove(at: srcIdx)
        jobs[jIdx].projects[pIdx].tasks.append(item)
        derivedStateIsDirty = true
        persist()
        registerUndoProjectTaskReorder(jobID: jobID, projectID: projectID, saved: saved)
    }

    func deleteJob(_ jobID: UUID) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        let job = jobs[jobIndex]
        let taskIDs = Set(
            job.jobTasks.map(\.id) + job.projects.flatMap(\.tasks).map(\.id)
        )
        let removedHistory = history.filter { event in
            guard let tid = event.taskID else { return false }
            return taskIDs.contains(tid)
        }
        let savedSelection = selection
        let savedIndex = jobIndex

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
        registerUndoDeleteJob(job: job, index: savedIndex, removedHistory: removedHistory, savedSelection: savedSelection)
    }

    private func registerUndoDeleteJob(job: Job, index: Int, removedHistory: [ActivityEvent], savedSelection: Selection?) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let insertAt = min(index, self.jobs.count)
                self.jobs.insert(job, at: insertAt)
                self.history.append(contentsOf: removedHistory)
                self.history.sort { $0.timestamp > $1.timestamp }
                if let savedSelection { self.selection = savedSelection }
                self.derivedStateIsDirty = true
                self.persist()
                self.registerRedoDeleteJob(jobID: job.id)
            }
        }
        appUndoManager.setActionName("Delete Job")
    }

    private func registerRedoDeleteJob(jobID: UUID) {

        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let job = jobs[jobIndex]
        let taskIDs = Set(job.jobTasks.map(\.id) + job.projects.flatMap(\.tasks).map(\.id))
        let removedHistory = history.filter { event in
            guard let tid = event.taskID else { return false }
            return taskIDs.contains(tid)
        }
        let savedSelection = selection
        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.deleteJob(jobID)
            }
        }
        _ = (job, removedHistory, savedSelection) // retain for redo chain via deleteJob
        appUndoManager.setActionName("Restore Job")
    }

    func deleteProject(jobID: UUID, projectID: UUID) {
        guard let location = projectLocation(jobID: jobID, projectID: projectID) else { return }

        let project = jobs[location.jobIndex].projects[location.projectIndex]
        let taskIDs = Set(project.tasks.map(\.id))
        let removedHistory = history.filter { event in
            guard let tid = event.taskID else { return false }
            return taskIDs.contains(tid)
        }
        let savedSelection = selection
        let projectIndex = location.projectIndex
        let wasPinned = nowPinnedProjectIDs.contains(projectID)

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
        registerUndoDeleteProject(
            project: project, jobID: jobID, projectIndex: projectIndex,
            removedHistory: removedHistory, savedSelection: savedSelection, wasPinned: wasPinned
        )
    }

    private func registerUndoDeleteProject(
        project: Project, jobID: UUID, projectIndex: Int,
        removedHistory: [ActivityEvent], savedSelection: Selection?, wasPinned: Bool
    ) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let jobIdx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                let insertAt = min(projectIndex, self.jobs[jobIdx].projects.count)
                self.jobs[jobIdx].projects.insert(project, at: insertAt)
                self.history.append(contentsOf: removedHistory)
                self.history.sort { $0.timestamp > $1.timestamp }
                if wasPinned, !self.nowPinnedProjectIDs.contains(project.id) {
                    self.nowPinnedProjectIDs.append(project.id)
                }
                if let savedSelection { self.selection = savedSelection }
                self.derivedStateIsDirty = true
                self.persist()


                self.appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.deleteProject(jobID: jobID, projectID: project.id)
                    }
                }
                self.appUndoManager.setActionName("Delete Project")
            }
        }
        appUndoManager.setActionName("Delete Project")
    }

    func setTaskStatus(_ context: TaskContext, status: TaskStatus, bypassMultitaskUpgradePrompt: Bool = false) {
        if status == .active, !bypassMultitaskUpgradePrompt, context.task.status != .active {
            if let note = parallelActiveLimitNote(forActivating: context) {
                parallelActiveLimitMessage = note
                return
            }
            if let offer = makeMultitaskUpgradeOffer(forActivating: context) {
                multitaskUpgradeOffer = offer
                return
            }
        }

        let base = taskContext(taskID: context.task.id) ?? context
        let nowOrdersBeforeStatus = captureNowOrdersForUndo()
        var taskSnapshotsBeforeStatus: [UUID: Task] = [base.task.id: base.task]
        if status == .active {
            for ctx in taskContexts where ctx.task.status == .active && ctx.task.id != base.task.id {
                taskSnapshotsBeforeStatus[ctx.task.id] = ctx.task
            }
        }

        let priorActives = activeTasks
        let selectionAfterCompletion = status == .done && selectedScreen == .now
            ? preferredNowSelectionAfterCompleting(base)
            : nil

        if status == .active {
            reconcileParallelActivesForActivating(base)
        }

        let cyclesOnCompletion = status == .done && (
            base.task.cadence == .repeatable ||
            (base.task.cadence == .kpi && (base.task.kpiRoundsRemaining ?? 0) > 0)
        )
        let completesFinally = status == .done && !cyclesOnCompletion

        updateTask(taskID: base.task.id) { task in
            if status == .done, task.cadence == .repeatable {
                task.progress = 0
                task.kpiCount = 0
                task.status = .queued
                task.nextAvailableAt = task.repeatEveryMinutes.map { .now.addingTimeInterval(Double($0 * 60)) }
            } else if status == .done, task.cadence == .kpi, let rounds = task.kpiRoundsRemaining, rounds > 0 {
                let delayMinutes = max(task.repeatEveryMinutes ?? 60, 1)
                task.progress = 0
                task.kpiCount = 0
                task.kpiRoundsRemaining = rounds - 1
                task.status = .queued
                task.nextAvailableAt = .now.addingTimeInterval(Double(delayMinutes * 60))
            } else if status == .active && task.progress == 0 {
                task.status = status
                if task.cadence != .kpi {
                    task.progress = 0.1
                }
                task.nextAvailableAt = nil
            } else {
                task.status = status
                task.nextAvailableAt = nil
                if status == .done {
                    task.progress = 1
                    if task.cadence == .kpi, let target = task.kpiTarget {
                        task.kpiCount = max(task.kpiCount, target)
                    }
                }
            }
        }

        if completesFinally {
            updateTask(taskID: base.task.id) { task in
                guard task.status == .done else { return }
                task.nowOrder = nextNowOrder()
            }
        }

        if status == .active, !base.task.energy.isMultitaskable {
            let others = priorActives.filter { $0.task.id != base.task.id }
            if let first = others.first {
                appendEvent(kind: .switched, context: first, detail: "Switched into \(base.task.title.lowercased()).")
            }
        }

        switch status {
        case .active:
            appendEvent(kind: .started, context: base, detail: "Started focus block.")
        case .paused:
            appendEvent(kind: .paused, context: base, detail: "Paused to protect the active thread.")
        case .waiting:
            appendEvent(kind: .waiting, context: base, detail: base.task.waitingOn ?? "Waiting on external progress.")
        case .done:
            if completesFinally {
                appendEvent(kind: .completed, context: base, detail: "Completed.")
                appendReflectionIfNeeded(for: base)
            } else {
                let resetCopy = taskContext(taskID: base.task.id) ?? base
                appendEvent(
                    kind: .completed,
                    context: resetCopy,
                    detail: repeatableCompletionDetail(for: resetCopy.task)
                )
            }
        case .queued:
            break
        }

        if status == .done, selectedScreen == .now {
            selection = selectionAfterCompletion
        } else {
            selection = nowSelection(for: base)
        }
        if status == .active {
            moveNowTaskToTop(taskID: base.task.id)
        }
        persist()
        registerUndoTaskMutation(
            taskSnapshotsBefore: taskSnapshotsBeforeStatus,
            nowOrdersBefore: nowOrdersBeforeStatus,
            actionName: undoActionName(for: status)
        )
    }

    func cancelMultitaskUpgradeOffer() {
        multitaskUpgradeOffer = nil
    }

    func clearParallelActiveLimitMessage() {
        parallelActiveLimitMessage = nil
    }

    /// Sets all offered tasks to `targetEnergy`, then activates the incoming task without prompting again.
    func confirmMultitaskUpgrade() {
        guard let offer = multitaskUpgradeOffer else { return }
        multitaskUpgradeOffer = nil
        let ids = Set(offer.participants.map(\.taskID))
        for tid in ids {
            updateTask(taskID: tid) { $0.energy = offer.targetEnergy }
        }
        persist()
        guard let ctx = taskContext(taskID: offer.incomingTaskID) else { return }
        setTaskStatus(ctx, status: .active, bypassMultitaskUpgradePrompt: true)
    }

    /// Dismisses the offer and starts only the new task (pauses other actives — previous default behavior).
    func confirmMultitaskUpgradeSwitchOnly() {
        guard let offer = multitaskUpgradeOffer else { return }
        multitaskUpgradeOffer = nil
        guard let ctx = taskContext(taskID: offer.incomingTaskID) else { return }
        setTaskStatus(ctx, status: .active, bypassMultitaskUpgradePrompt: true)
    }

    /// Uses the current `selection` task (any screen). No-op if selection is not a task.
    func applyStatusToSelectedTask(_ status: TaskStatus) {
        guard let ctx = selectedTaskContext else { return }
        setTaskStatus(ctx, status: status)
    }

    func incrementProgress(_ context: TaskContext, by amount: Double = 0.15) {
        guard let live = taskContext(taskID: context.task.id) else { return }
        let newProgress = min(live.task.progress + amount, 1)
        if newProgress >= 1 {
            setTaskStatus(live, status: .done)
            return
        }
        let snapshotBefore = live.task
        let nowOrdersBefore = captureNowOrdersForUndo()
        updateTask(taskID: live.task.id) { $0.progress = newProgress }
        persist()
        registerUndoTaskMutation(
            taskSnapshotsBefore: [snapshotBefore.id: snapshotBefore],
            nowOrdersBefore: nowOrdersBefore,
            actionName: "Increment Progress"
        )
    }

    func adjustKpiCount(_ context: TaskContext, delta: Int) {
        guard delta != 0 else { return }
        guard let live = taskContext(taskID: context.task.id), live.task.cadence == .kpi else { return }

        let snapshotBefore = live.task
        let nowOrdersBefore = captureNowOrdersForUndo()
        let target = max(live.task.kpiTarget ?? 1, 1)
        let nextCount = max(0, min(target, live.task.kpiCount + delta))
        updateTask(taskID: live.task.id) { task in
            task.kpiCount = nextCount
            task.progress = min(Double(nextCount) / Double(target), 1)
        }
        persist()

        if nextCount >= target, let refreshed = taskContext(taskID: live.task.id) {
            setTaskStatus(refreshed, status: .done)
            registerUndoTaskMutation(
                taskSnapshotsBefore: [snapshotBefore.id: snapshotBefore],
                nowOrdersBefore: nowOrdersBefore,
                actionName: "Increment KPI"
            )
            return
        }

        if let refreshed = taskContext(taskID: live.task.id) {
            let verb = delta > 0 ? "Counted" : "Adjusted"
            let detail = refreshed.task.kpiCounterLabel.map { "\(verb): \($0)." } ?? "\(verb) KPI."
            appendEvent(kind: .counted, context: refreshed, detail: detail)
        }

        registerUndoTaskMutation(
            taskSnapshotsBefore: [snapshotBefore.id: snapshotBefore],
            nowOrdersBefore: nowOrdersBefore,
            actionName: delta > 0 ? "Increment KPI" : "Decrement KPI"
        )
    }

    func toggleTaskNow(_ context: TaskContext) {
        let base = taskContext(taskID: context.task.id) ?? context
        let nowOrdersBeforeToggle = captureNowOrdersForUndo()
        let snapshotBefore = base.task

        updateTask(taskID: base.task.id) { task in
            task.isScheduledNow.toggle()
            if task.isScheduledNow {
                task.isArchived = false
                task.archivedAt = nil
                task.nowOrder = nextNowOrder()
            }
        }
        persist()
        registerUndoTaskMutation(
            taskSnapshotsBefore: [snapshotBefore.id: snapshotBefore],
            nowOrdersBefore: nowOrdersBeforeToggle,
            actionName: "Toggle Now"
        )
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

        let ordersBefore = captureNowOrdersForUndo()
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
        registerUndoRestoringNowOrders(ordersBefore)
    }

    /// Move a Now task to the end of the list (e.g. drop on trailing drop zone).
    func reorderNowTaskToEnd(_ movingTaskID: UUID) {
        let ordersBefore = captureNowOrdersForUndo()
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
        registerUndoRestoringNowOrders(ordersBefore)
    }

    private func captureNowOrdersForUndo() -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: nowTasks.map { ($0.task.id, $0.task.nowOrder) })
    }

    private func applyNowOrders(_ orders: [UUID: Double]) {
        for (id, order) in orders {
            updateTask(taskID: id) { $0.nowOrder = order }
        }
        persist()
    }

    // MARK: - Set task energy (right-click change type)

    func setTaskEnergy(_ context: TaskContext, energy: TaskEnergy) {
        guard context.task.energy != energy else { return }
        let snapshot = context.task
        updateTask(context: context) { task in
            task.energy = energy
        }
        appUndoManager.registerUndo(withTarget: self) { store in
            store.restoreTaskSnapshot(snapshot)
        }
        appUndoManager.setActionName("Change Type")
    }

    // MARK: - Day Planner (semi-automatic arrangement)

    enum DayPlannerSortKey: String, CaseIterable, Identifiable {
        case energy
        case job
        case priority
        case status
        case cadence

        var id: String { rawValue }

        var title: String {
            switch self {
            case .energy: "Energy Type"
            case .job: "Job"
            case .priority: "Priority"
            case .status: "Status"
            case .cadence: "Cadence"
            }
        }
    }

    /// Returns sorted open Now task IDs based on the chosen sort criteria. Done tasks are excluded.
    func sortedNowTaskIDs(
        primary: DayPlannerSortKey,
        secondary: DayPlannerSortKey?,
        primaryDescending: Bool = true,
        secondaryDescending: Bool = true
    ) -> [UUID] {
        let open = nowTasks.filter { $0.task.status != .done && !$0.task.isArchived }
        let sorted = open.sorted { a, b in
            let cmp = compareTasks(a, b, key: primary, descending: primaryDescending)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            if let secondary {
                let cmp2 = compareTasks(a, b, key: secondary, descending: secondaryDescending)
                if cmp2 != .orderedSame { return cmp2 == .orderedAscending }
            }
            return a.task.nowOrder < b.task.nowOrder
        }
        return sorted.map(\.task.id)
    }

    /// Returns the full sorted preview (task contexts) for display purposes.
    func sortedNowTaskContexts(
        primary: DayPlannerSortKey,
        secondary: DayPlannerSortKey?,
        primaryDescending: Bool = true,
        secondaryDescending: Bool = true
    ) -> [TaskContext] {
        let ids = sortedNowTaskIDs(
            primary: primary,
            secondary: secondary,
            primaryDescending: primaryDescending,
            secondaryDescending: secondaryDescending
        )
        return ids.compactMap { id in taskContext(taskID: id) }
    }

    /// Applies the given task ID order to Now. Done tasks stay at the end with their existing order.
    func applyNowListOrder(sortedTaskIDs: [UUID]) {
        let ordersBefore = captureNowOrdersForUndo()

        // Assign sequential orders to the sorted open tasks
        for (index, taskID) in sortedTaskIDs.enumerated() {
            updateTask(taskID: taskID) { task in
                task.nowOrder = Double(index)
            }
        }

        // Push done tasks after the sorted ones
        let doneTasks = nowTasks.filter { $0.task.status == .done }
        let doneBase = Double(sortedTaskIDs.count)
        for (offset, ctx) in doneTasks.enumerated() {
            updateTask(taskID: ctx.task.id) { task in
                task.nowOrder = doneBase + Double(offset)
            }
        }

        persist()
        registerUndoRestoringNowOrders(ordersBefore)
    }

    private func compareTasks(_ a: TaskContext, _ b: TaskContext, key: DayPlannerSortKey, descending: Bool) -> ComparisonResult {
        let result: ComparisonResult
        switch key {
        case .energy:
            let aIdx = TaskEnergy.allCases.firstIndex(of: a.task.energy) ?? 0
            let bIdx = TaskEnergy.allCases.firstIndex(of: b.task.energy) ?? 0
            result = aIdx < bIdx ? .orderedAscending : (aIdx > bIdx ? .orderedDescending : .orderedSame)
        case .job:
            result = a.jobTitle.localizedCaseInsensitiveCompare(b.jobTitle)
        case .priority:
            result = a.task.priority < b.task.priority ? .orderedAscending : (a.task.priority > b.task.priority ? .orderedDescending : .orderedSame)
        case .status:
            let aIdx = TaskStatus.allCases.firstIndex(of: a.task.status) ?? 0
            let bIdx = TaskStatus.allCases.firstIndex(of: b.task.status) ?? 0
            result = aIdx < bIdx ? .orderedAscending : (aIdx > bIdx ? .orderedDescending : .orderedSame)
        case .cadence:
            let aIdx = TaskCadence.allCases.firstIndex(of: a.task.cadence) ?? 0
            let bIdx = TaskCadence.allCases.firstIndex(of: b.task.cadence) ?? 0
            result = aIdx < bIdx ? .orderedAscending : (aIdx > bIdx ? .orderedDescending : .orderedSame)
        }
        if descending {
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }
        return result
    }

    private func restoreTaskSnapshot(_ snapshot: Task) {
        updateTask(taskID: snapshot.id) { task in
            task.applyFullState(from: snapshot)
        }
    }

    private func undoActionName(for status: TaskStatus) -> String {
        switch status {
        case .active: "Start Task"
        case .paused: "Pause Task"
        case .waiting: "Set Waiting"
        case .done: "Complete Task"
        case .queued: "Set Not Started"
        }
    }

    /// Restores task snapshots and Now ordering, and registers redo (mirrors `registerUndoRestoringNowOrders` chaining).
    private func registerUndoTaskMutation(
        taskSnapshotsBefore: [UUID: Task],
        nowOrdersBefore: [UUID: Double],
        actionName: String
    ) {

        guard !taskSnapshotsBefore.isEmpty else { return }
        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                var redoSnaps: [UUID: Task] = [:]
                for id in taskSnapshotsBefore.keys {
                    if let ctx = self.taskContext(taskID: id) {
                        redoSnaps[id] = ctx.task
                    }
                }
                let redoOrders = self.captureNowOrdersForUndo()
                self.applyNowOrders(nowOrdersBefore)
                for snap in taskSnapshotsBefore.values {
                    self.restoreTaskSnapshot(snap)
                }
                self.derivedStateIsDirty = true
                self.persist()
                self.registerUndoTaskMutation(
                    taskSnapshotsBefore: redoSnaps,
                    nowOrdersBefore: redoOrders,
                    actionName: actionName
                )
            }
        }
        appUndoManager.setActionName(actionName)
    }

    /// Registers with the app undo manager so ⌘Z / Edit ▸ Undo restores prior `nowOrder` values (chains for redo).
    private func registerUndoRestoringNowOrders(_ ordersToRestore: [UUID: Double]) {

        appUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let snapshotBeforeUndo = self.captureNowOrdersForUndo()
                self.applyNowOrders(ordersToRestore)
                self.registerUndoRestoringNowOrders(snapshotBeforeUndo)
            }
        }
        appUndoManager.setActionName("Move on Now")
    }

    func setDailyCapacityMinutes(_ minutes: Int) {
        dailyCapacityMinutes = minutes
        persist()
    }

    func setDayBatteryStartMinutes(_ minutes: Int) {
        let clamped = min(max(minutes, 0), 1439)
        guard dayBatteryStartMinutes != clamped else { return }
        dayBatteryStartMinutes = clamped
        persist()
    }

    func setDayBatteryEndMinutes(_ minutes: Int) {
        let clamped = min(max(minutes, 0), 1439)
        guard dayBatteryEndMinutes != clamped else { return }
        dayBatteryEndMinutes = clamped
        persist()
    }

    func setDayBatteryShowsPercentageInMenuBar(_ isEnabled: Bool) {
        guard dayBatteryShowsPercentageInMenuBar != isEnabled else { return }
        dayBatteryShowsPercentageInMenuBar = isEnabled
        persist()
    }

    func setDayBatteryUsesWideMenuBarItem(_ isEnabled: Bool) {
        guard dayBatteryUsesWideMenuBarItem != isEnabled else { return }
        dayBatteryUsesWideMenuBarItem = isEnabled
        persist()
    }

    func setTaskAutoArchiveAfterIdleHours(_ hours: Int) {
        let clamped = min(max(hours, 0), 24 * 365)
        guard taskAutoArchiveAfterIdleHours != clamped else { return }
        taskAutoArchiveAfterIdleHours = clamped
        persist()
    }

    func setDoneTaskAutoArchiveAfterDays(_ days: Int) {
        let clamped = min(max(days, 0), 3650)
        guard doneTaskAutoArchiveAfterDays != clamped else { return }
        doneTaskAutoArchiveAfterDays = clamped
        persist()
    }

    func setArchivedTaskPurgeAfterDays(_ days: Int) {
        let clamped = min(max(days, 0), 3650)
        guard archivedTaskPurgeAfterDays != clamped else { return }
        archivedTaskPurgeAfterDays = clamped
        persist()
    }

    /// Archives or restores a task. Archiving removes it from Now and normal job/project lists.
    func setTaskArchived(_ context: TaskContext, archived: Bool) {
        let snapshotBefore = context.task
        let nowOrdersBefore = captureNowOrdersForUndo()
        updateTask(taskID: context.task.id) { task in
            task.isArchived = archived
            if archived {
                task.isScheduledNow = false
                task.archivedAt = Date.now
            } else {
                task.archivedAt = nil
            }
        }
        persist()
        registerUndoTaskMutation(
            taskSnapshotsBefore: [snapshotBefore.id: snapshotBefore],
            nowOrdersBefore: nowOrdersBefore,
            actionName: archived ? "Archive Task" : "Restore Task"
        )
    }

    /// Runs idle auto-archive if enabled (throttled). Call when the app becomes active or on launch.
    func applyIdleTaskAutoArchiveIfNeeded() {
        guard taskAutoArchiveAfterIdleHours > 0 else { return }
        let now = Date.now
        if let last = lastIdleAutoArchiveAt, now.timeIntervalSince(last) < 45 {
            return
        }
        lastIdleAutoArchiveAt = now

        let cutoff = now.addingTimeInterval(-Double(taskAutoArchiveAfterIdleHours) * 3600)
        let activityByTask = Self.latestActivityTimestampByTaskID(from: history)
        var didArchiveAny = false

        for context in taskContexts {
            let task = context.task
            guard !task.isArchived else { continue }
            guard task.status != .done, task.status != .active else { continue }
            guard let lastTouch = activityByTask[task.id], lastTouch < cutoff else { continue }

            updateTask(taskID: task.id) { t in
                guard !t.isArchived else { return }
                guard t.status != .done, t.status != .active else { return }
                t.isArchived = true
                t.isScheduledNow = false
                t.archivedAt = Date.now
            }
            didArchiveAny = true
        }
        if didArchiveAny {
            persist()
        }
    }

    /// Moves **done** tasks into the archive after the configured delay from their last completion event.
    func applyDoneTaskAutoArchiveIfNeeded() {
        guard doneTaskAutoArchiveAfterDays > 0 else { return }
        let now = Date.now
        if let last = lastDoneAutoArchiveAt, now.timeIntervalSince(last) < 45 {
            return
        }
        lastDoneAutoArchiveAt = now

        let threshold = Double(doneTaskAutoArchiveAfterDays) * 86400
        let activityByTask = Self.latestActivityTimestampByTaskID(from: history)
        var didArchiveAny = false

        for context in taskContexts {
            let task = context.task
            guard task.status == .done, !task.isArchived else { continue }
            let completedAt = latestCompletionTimestamp(for: task.id)
                ?? activityByTask[task.id]
                ?? .distantPast
            guard now.timeIntervalSince(completedAt) >= threshold else { continue }

            updateTask(taskID: task.id) { t in
                guard t.status == .done, !t.isArchived else { return }
                t.isArchived = true
                t.isScheduledNow = false
                t.archivedAt = Date.now
            }
            didArchiveAny = true
        }
        if didArchiveAny {
            persist()
        }
    }

    /// Permanently removes archived tasks past the retention window (no undo). Completion metrics stay in the activity log.
    func applyArchivedTaskAutoDeleteIfNeeded() {
        guard archivedTaskPurgeAfterDays > 0 else { return }
        let now = Date.now
        if let last = lastArchivedPurgeAt, now.timeIntervalSince(last) < 45 {
            return
        }
        lastArchivedPurgeAt = now

        let window = Double(archivedTaskPurgeAfterDays) * 86400
        let victims = archivedTaskContexts.filter { ctx in
            let start = ctx.task.archivedAt ?? latestCompletionTimestamp(for: ctx.task.id) ?? .distantPast
            return now.timeIntervalSince(start) >= window
        }
        guard !victims.isEmpty else { return }

        for ctx in victims {
            guard ctx.task.isArchived, let payload = makeDeleteTaskPayload(removing: ctx) else { continue }
            applyDeleteTaskPayload(payload)
        }
        persist()
    }

    private func scrubHistoryPreservingMetrics(removingTaskID tid: UUID) {
        history = history.compactMap { event in
            guard event.taskID == tid else { return event }
            switch event.kind {
            case .completed, .focusRated, .qualityRated:
                return ActivityEvent(
                    id: event.id,
                    timestamp: event.timestamp,
                    kind: event.kind,
                    taskID: nil,
                    taskTitle: event.taskTitle,
                    projectTitle: event.projectTitle,
                    detail: event.detail,
                    focusRating: event.focusRating,
                    qualityRating: event.qualityRating,
                    sessionMinutes: event.sessionMinutes
                )
            default:
                return nil
            }
        }
    }

    private func migrateArchivedTimestampsIfNeeded() {
        guard persistenceEnabled else { return }
        var changed = false
        for ctx in taskContexts where ctx.task.isArchived && ctx.task.archivedAt == nil {
            let stamp = latestCompletionTimestamp(for: ctx.task.id) ?? Date.now
            updateTask(taskID: ctx.task.id) { task in
                task.archivedAt = stamp
            }
            changed = true
        }
        if changed {
            persist()
        }
    }

    private func latestCompletionTimestamp(for taskID: UUID) -> Date? {
        history.filter { $0.taskID == taskID && $0.kind == .completed }.map(\.timestamp).max()
    }

    private static func latestActivityTimestampByTaskID(from history: [ActivityEvent]) -> [UUID: Date] {
        var map: [UUID: Date] = [:]
        for event in history {
            guard let id = event.taskID else { continue }
            let t = event.timestamp
            if let existing = map[id] {
                if t > existing { map[id] = t }
            } else {
                map[id] = t
            }
        }
        return map
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

        // Single-pass: bucket events by day offset (0 = today, 1 = yesterday, etc.)
        var buckets: [Int: [ActivityEvent]] = [:]
        for event in history {
            let eventDay = calendar.startOfDay(for: event.timestamp)
            let offset = calendar.dateComponents([.day], from: eventDay, to: today).day ?? daysBack
            guard offset >= 0, offset < daysBack else { continue }
            buckets[offset, default: []].append(event)
        }

        return (0..<daysBack).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let items = buckets[offset] ?? []
            return ActivitySummary(
                date: date,
                completions: items.filter { $0.kind == .completed }.count,
                focusAverage: average(items.compactMap(\.focusRating))
            )
        }
    }

    var visibleNowJobIDs: [UUID] {
        ensureDerivedState()
        return cachedVisibleNowJobIDs
    }

    var visibleNowJobs: [Job] {
        ensureDerivedState()
        return cachedVisibleNowJobIDs.compactMap { id in cachedJobsByID[id] }
    }

    var visibleNowProjectIDs: [UUID] {
        ensureDerivedState()
        return cachedVisibleNowProjectIDs
    }

    var visibleNowProjects: [ProjectContext] {
        ensureDerivedState()
        return cachedVisibleNowProjectIDs.compactMap { id in cachedProjectsByID[id] }
    }

    var scopedNowTasks: [TaskContext] {
        ensureDerivedState()
        return cachedScopedNowTasks
    }

    var workedMinutesToday: Int {
        ensureDerivedState()
        return cachedWorkedMinutesToday
    }

    var workedMinutesRemaining: Int {
        max(dailyCapacityMinutes - workedMinutesToday, 0)
    }

    var workdayProgress: Double {
        guard dailyCapacityMinutes > 0 else { return 0 }
        return min(Double(workedMinutesToday) / Double(dailyCapacityMinutes), 1)
    }

    var nowTreeGroups: [[TaskContext]] {
        ensureDerivedState()
        return cachedNowTreeGroups
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
        case .manual:
            return false
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

    private func parallelActiveLimitNote(forActivating incoming: TaskContext) -> String? {
        let others = activeTasks.filter { $0.task.id != incoming.task.id }
        guard others.count + 1 > 4 else { return nil }
        return "Turbo supports at most four in-progress tasks in one bundle. Pause or finish one task before starting another."
    }

    private func makeMultitaskUpgradeOffer(forActivating incoming: TaskContext) -> MultitaskUpgradeOffer? {
        let others = activeTasks.filter { $0.task.id != incoming.task.id }
        guard !others.isEmpty else { return nil }
        let proposed = others + [incoming]
        if isCompatibleParallelBundle(proposed) { return nil }
        guard proposed.count <= 4 else { return nil }
        guard let target = TaskEnergy.multitaskEnergy(forParallelBundleCount: proposed.count) else { return nil }

        let participants = proposed.map { ctx in
            MultitaskUpgradeOffer.Participant(
                taskID: ctx.task.id,
                title: ctx.task.title,
                currentEnergyLabel: ctx.task.energy.title
            )
        }
        return MultitaskUpgradeOffer(
            id: UUID(),
            participants: participants,
            targetEnergy: target,
            incomingTaskID: incoming.task.id
        )
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
        suppressDidSetPersistence = true
        defer { suppressDidSetPersistence = false }

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
        suppressDidSetPersistence = true
        defer { suppressDidSetPersistence = false }

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
        suppressDidSetPersistence = true
        defer { suppressDidSetPersistence = false }

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

            let openWorkCount = job.jobTasks.filter { !$0.isArchived && $0.status != .done }.count
                + job.projects.flatMap(\.tasks).filter { !$0.isArchived && $0.status != .done }.count

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

        cachedActiveTasks = taskContexts.filter { !$0.task.isArchived && $0.task.status == .active }
        cachedOpenTaskCount = taskContexts.filter { !$0.task.isArchived && $0.task.status != .done }.count
        cachedCompletionCount = history.filter { $0.kind == .completed }.count
        cachedWaitingTaskCount = taskContexts.filter { !$0.task.isArchived && $0.task.status == .waiting }.count

        let candidates = taskContexts.filter {
            !$0.task.isArchived && $0.task.isScheduledNow && $0.task.isAvailableNow
        }
        let openNow = candidates.filter { $0.task.status != .done }.sorted(by: sortTasksForNow)
        let doneNow = candidates.filter { $0.task.status == .done }.sorted(by: sortTasksForNow)
        cachedNowTasks = openNow + doneNow
        cachedPlan = ExecutionPlanner.buildPlan(from: openNow)

        let mergedJobIDs = buildMergedNowJobIDs()
        let suppressed = Set(nowSuppressedJobIDs)
        cachedVisibleNowJobIDs = mergedJobIDs.filter { !suppressed.contains($0) }

        let mergedProjectIDs = buildMergedNowProjectIDs(
            visibleJobIDs: Set(cachedVisibleNowJobIDs)
        )
        let suppressedProjects = Set(nowSuppressedProjectIDs)
        cachedVisibleNowProjectIDs = mergedProjectIDs.filter { !suppressedProjects.contains($0) }

        let jobIDSet = Set(cachedVisibleNowJobIDs)
        let projectIDSet = Set(cachedVisibleNowProjectIDs)
        cachedScopedNowTasks = cachedNowTasks.filter { context in
            let matchesJob = jobIDSet.isEmpty || (context.jobID.map { jobIDSet.contains($0) } ?? true)
            let matchesProject = projectIDSet.isEmpty || (context.projectID.map { projectIDSet.contains($0) } ?? true)
            return matchesJob && matchesProject
        }
        cachedNowTreeGroups = makeCompatibleNowGroups(from: cachedScopedNowTasks.filter { $0.task.status != .done })

        // Cache today metrics to avoid full history scans per frame.
        let today = calendar.startOfDay(for: .now)
        let todayEvents = history.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
        let todayTotals = Dictionary(grouping: todayEvents) { $0.taskID ?? UUID() }
        cachedWorkedMinutesToday = todayTotals.values.reduce(0) { total, events in
            total + (events.compactMap(\.sessionMinutes).max() ?? 0)
        }

        let focusRatings = history.compactMap(\.focusRating)
        cachedFocusRatingAverage = focusRatings.isEmpty ? 0 : Double(focusRatings.reduce(0, +)) / Double(focusRatings.count)

        let qualityRatings = history.compactMap(\.qualityRating)
        cachedQualityRatingAverage = qualityRatings.isEmpty ? 0 : Double(qualityRatings.reduce(0, +)) / Double(qualityRatings.count)

        derivedStateIsDirty = false
    }

    private func buildMergedNowJobIDs() -> [UUID] {
        let automatic = cachedNowTasks
            .compactMap(\.jobID)
        let manual = nowPinnedJobIDs.filter { id in
            cachedJobsByID[id] != nil
        }
        return orderedUnion(primary: automatic, secondary: manual)
    }

    private func buildMergedNowProjectIDs(visibleJobIDs: Set<UUID>) -> [UUID] {
        let automatic = cachedProjectContexts
            .filter { context in
                guard visibleJobIDs.contains(context.jobID) else { return false }
                let scopeKey = TaskScopeKey(jobID: context.jobID, projectID: context.project.id)
                let tasks = cachedTaskContextsByScope[scopeKey] ?? []
                return tasks.contains { $0.task.isScheduledNow && $0.task.isAvailableNow && !$0.task.isArchived }
            }
            .map(\.project.id)
        let manual = nowPinnedProjectIDs.filter { id in
            cachedProjectsByID[id] != nil
        }
        return orderedUnion(primary: automatic, secondary: manual)
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

    private func initialNowOrderForNewTask(isScheduledNow: Bool) -> Double {
        guard isScheduledNow else { return 0 }
        switch newNowTaskPlacement {
        case .bottom:
            return nextNowOrder()
        case .top:
            return nextTopNowOrderBelowActiveTasks()
        }
    }

    private func nextTopNowOrderBelowActiveTasks() -> Double {
        let scheduled = nowTasks.filter(\.task.isScheduledNow)
        let activeMax = scheduled
            .filter { $0.task.status == .active }
            .map(\.task.nowOrder)
            .max()
        let nonActiveMin = scheduled
            .filter { $0.task.status != .active }
            .map(\.task.nowOrder)
            .min()

        switch (activeMax, nonActiveMin) {
        case (nil, nil):
            return 0
        case (nil, let first?):
            return first - 1
        case (let last?, nil):
            return last + 1
        case (let last?, let first?):
            return last < first ? last + ((first - last) / 2) : first - 1
        }
    }

    private func returnNowOrdersBelowActiveTasks(count: Int) -> [Double] {
        guard count > 0 else { return [] }

        let scheduled = nowTasks.filter(\.task.isScheduledNow)
        let activeMax = scheduled
            .filter { $0.task.status == .active }
            .map(\.task.nowOrder)
            .max()
        let nonActiveMin = scheduled
            .filter { $0.task.status != .active }
            .map(\.task.nowOrder)
            .min()

        switch (activeMax, nonActiveMin) {
        case (nil, nil):
            return Array(0..<count).map(Double.init)
        case (nil, let first?):
            return Array(0..<count).map { first - Double(count - $0) }
        case (let last?, nil):
            return Array(0..<count).map { last + Double($0 + 1) }
        case (let last?, let first?):
            guard last < first else {
                return Array(0..<count).map { last + Double($0 + 1) }
            }
            let gap = (first - last) / Double(count + 1)
            return Array(0..<count).map { last + gap * Double($0 + 1) }
        }
    }

    func releaseTasksReadyToReturnIfNeeded() {
        let ready = taskContexts
            .filter { context in
                context.task.isScheduledNow
                    && context.task.status == .queued
                    && context.task.nextAvailableAt != nil
                    && context.task.isAvailableNow
            }
            .sorted {
                ($0.task.nextAvailableAt ?? .distantPast) < ($1.task.nextAvailableAt ?? .distantPast)
            }

        guard !ready.isEmpty else { return }
        let orders = returnNowOrdersBelowActiveTasks(count: ready.count)

        for (context, order) in zip(ready, orders) {
            updateTask(taskID: context.task.id) { task in
                task.nextAvailableAt = nil
                task.nowOrder = order
            }
        }
        persist()
    }

    private func repeatableCompletionDetail(for task: Task) -> String {
        if task.cadence == .kpi {
            let delayText = task.repeatEveryMinutes.map { "Back in \($0)m." }
            if let rounds = task.kpiRoundsRemaining, rounds > 0 {
                let roundsText = rounds == 1 ? "Round reset. 1 round left." : "Round reset. \(rounds) rounds left."
                if let delayText { return "\(roundsText) \(delayText)" }
                return roundsText
            }
            if task.status != .done {
                if let delayText { return "Round reset. Final round. \(delayText)" }
                return "Round reset. Final round."
            }
            return "KPI completed."
        }

        guard let repeatEveryMinutes = task.repeatEveryMinutes else {
            return "Repeatable reset."
        }
        return "Returns in \(repeatEveryMinutes)m."
    }

    private func persist() {
        trimHistoryIfNeeded()
        schedulePersistenceIfNeeded()
    }

    /// Drops oldest non-metric events when history exceeds the cap.
    private func trimHistoryIfNeeded() {
        let cap = Self.historyEventCap
        guard history.count > cap else { return }
        // Metric events (completed, focusRated, qualityRated) are preserved for lifetime stats.
        let metricKinds: Set<ActivityKind> = [.completed, .focusRated, .qualityRated]
        // history is sorted newest-first; walk from the back removing operational events.
        var trimmed = history
        var removeCount = trimmed.count - cap
        var i = trimmed.count - 1
        while removeCount > 0, i >= 0 {
            if !metricKinds.contains(trimmed[i].kind) {
                trimmed.remove(at: i)
                removeCount -= 1
            }
            i -= 1
        }
        if trimmed.count != history.count {
            history = trimmed
        }
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
            dayBatteryStartMinutes: dayBatteryStartMinutes,
            dayBatteryEndMinutes: dayBatteryEndMinutes,
            dayBatteryShowsPercentageInMenuBar: dayBatteryShowsPercentageInMenuBar,
            dayBatteryUsesWideMenuBarItem: dayBatteryUsesWideMenuBarItem,
            taskAutoArchiveAfterIdleHours: taskAutoArchiveAfterIdleHours,
            doneTaskAutoArchiveAfterDays: doneTaskAutoArchiveAfterDays,
            archivedTaskPurgeAfterDays: archivedTaskPurgeAfterDays,
            tasksPresentation: tasksPresentation,
            themeMode: themeMode,
            nowPinnedJobIDs: nowPinnedJobIDs.filter { validJobIDs.contains($0) },
            nowPinnedProjectIDs: nowPinnedProjectIDs.filter { validProjectIDs.contains($0) },
            nowSuppressedJobIDs: nowSuppressedJobIDs.filter { validJobIDs.contains($0) },
            nowSuppressedProjectIDs: nowSuppressedProjectIDs.filter { validProjectIDs.contains($0) },
            focusCardDensity: focusCardDensity,
            newNowTaskPlacement: newNowTaskPlacement,
            focusOverlayPresenceMode: focusOverlayPresenceMode,
            focusOverlayWindowFrame: focusOverlayWindowFrame,
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
            dayBatteryStartMinutes: snapshot.dayBatteryStartMinutes,
            dayBatteryEndMinutes: snapshot.dayBatteryEndMinutes,
            dayBatteryShowsPercentageInMenuBar: snapshot.dayBatteryShowsPercentageInMenuBar,
            dayBatteryUsesWideMenuBarItem: snapshot.dayBatteryUsesWideMenuBarItem,
            taskAutoArchiveAfterIdleHours: snapshot.taskAutoArchiveAfterIdleHours,
            doneTaskAutoArchiveAfterDays: snapshot.doneTaskAutoArchiveAfterDays,
            archivedTaskPurgeAfterDays: snapshot.archivedTaskPurgeAfterDays,
            themeMode: snapshot.themeMode,
            nowPinnedJobIDs: snapshot.nowPinnedJobIDs,
            nowPinnedProjectIDs: snapshot.nowPinnedProjectIDs,
            nowSuppressedJobIDs: snapshot.nowSuppressedJobIDs,
            nowSuppressedProjectIDs: snapshot.nowSuppressedProjectIDs,
            focusCardDensity: snapshot.focusCardDensity,
            newNowTaskPlacement: snapshot.newNowTaskPlacement,
            focusOverlayPresenceMode: snapshot.focusOverlayPresenceMode,
            focusOverlayWindowFrame: snapshot.focusOverlayWindowFrame,
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
            dayBatteryStartMinutes: 8 * 60,
            dayBatteryEndMinutes: 0,
            dayBatteryShowsPercentageInMenuBar: true,
            dayBatteryUsesWideMenuBarItem: false,
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
                                kpiTarget: 10,
                                kpiRoundsRemaining: 2
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
