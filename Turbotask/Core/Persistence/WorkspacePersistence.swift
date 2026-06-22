//
//  WorkspacePersistence.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import Foundation

/// AppKit window frame for the floating focus card (origin is bottom-left, like `NSRect`).
struct FocusOverlayWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// Decodes legacy `weekPlanEntries` from older workspace files and discards them.
private struct LegacyWeekPlanEntry: Codable {
    let id: UUID
    let jobID: UUID
    let weekStart: Date
    let dayOfWeek: Int
    let position: Int
}

struct WorkspaceSnapshot: Codable {
    var jobs: [Job]
    /// Tasks with no job (optional top-level inbox).
    var standaloneTasks: [Task]
    var history: [ActivityEvent]
    var dailyCapacityMinutes: Int
    var dayBatteryStartMinutes: Int
    var dayBatteryEndMinutes: Int
    var dayBatteryShowsPercentageInMenuBar: Bool
    var dayBatteryUsesWideMenuBarItem: Bool
    /// 0 = off. Otherwise archive incomplete, non-active tasks after this many hours without activity log entries.
    var taskAutoArchiveAfterIdleHours: Int
    /// 0 = off. Otherwise archive **done** tasks this many full days after their last completion event.
    var doneTaskAutoArchiveAfterDays: Int
    /// 0 = never. Otherwise permanently remove archived tasks this many days after `archivedAt` (completion used as fallback when unset).
    var archivedTaskPurgeAfterDays: Int
    var tasksPresentation: TasksPresentationState
    var themeMode: AppThemeMode
    var nowPinnedJobIDs: [UUID]
    /// Jobs the user removed from the Today scope bar (stays hidden while tasks remain on Now).
    var nowSuppressedJobIDs: [UUID]
    var focusCardDensity: FocusCardDensity
    var newNowTaskPlacement: NewNowTaskPlacement
    /// Spaces behavior for the floating focus card (`canJoinAllSpaces` vs current desktop only).
    var focusOverlayPresenceMode: FocusOverlayPresenceMode
    /// Last known `NSRect` of the focus overlay panel; used to restore position across hide/show and launches.
    var focusOverlayWindowFrame: FocusOverlayWindowFrame?
    var trainingWheelsEnabled: Bool
    var typeaheadListNavigationEnabled: Bool

    init(
        jobs: [Job],
        standaloneTasks: [Task] = [],
        history: [ActivityEvent],
        dailyCapacityMinutes: Int,
        dayBatteryStartMinutes: Int = 8 * 60,
        dayBatteryEndMinutes: Int = 0,
        dayBatteryShowsPercentageInMenuBar: Bool = true,
        dayBatteryUsesWideMenuBarItem: Bool = false,
        taskAutoArchiveAfterIdleHours: Int = 0,
        doneTaskAutoArchiveAfterDays: Int = 0,
        archivedTaskPurgeAfterDays: Int = 0,
        tasksPresentation: TasksPresentationState = TasksPresentationState(),
        themeMode: AppThemeMode = .system,
        nowPinnedJobIDs: [UUID] = [],
        nowSuppressedJobIDs: [UUID] = [],
        focusCardDensity: FocusCardDensity = .standard,
        newNowTaskPlacement: NewNowTaskPlacement = .bottom,
        focusOverlayPresenceMode: FocusOverlayPresenceMode = .allDesktops,
        focusOverlayWindowFrame: FocusOverlayWindowFrame? = nil,
        trainingWheelsEnabled: Bool = true,
        typeaheadListNavigationEnabled: Bool = true
    ) {
        self.jobs = jobs
        self.standaloneTasks = standaloneTasks
        self.history = history
        self.dailyCapacityMinutes = dailyCapacityMinutes
        self.dayBatteryStartMinutes = dayBatteryStartMinutes
        self.dayBatteryEndMinutes = dayBatteryEndMinutes
        self.dayBatteryShowsPercentageInMenuBar = dayBatteryShowsPercentageInMenuBar
        self.dayBatteryUsesWideMenuBarItem = dayBatteryUsesWideMenuBarItem
        self.taskAutoArchiveAfterIdleHours = taskAutoArchiveAfterIdleHours
        self.doneTaskAutoArchiveAfterDays = doneTaskAutoArchiveAfterDays
        self.archivedTaskPurgeAfterDays = archivedTaskPurgeAfterDays
        self.tasksPresentation = tasksPresentation
        self.themeMode = themeMode
        self.nowPinnedJobIDs = nowPinnedJobIDs
        self.nowSuppressedJobIDs = nowSuppressedJobIDs
        self.focusCardDensity = focusCardDensity
        self.newNowTaskPlacement = newNowTaskPlacement
        self.focusOverlayPresenceMode = focusOverlayPresenceMode
        self.focusOverlayWindowFrame = focusOverlayWindowFrame
        self.trainingWheelsEnabled = trainingWheelsEnabled
        self.typeaheadListNavigationEnabled = typeaheadListNavigationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case jobs
        case standaloneTasks
        case history
        case dailyCapacityMinutes
        case dayBatteryStartMinutes
        case dayBatteryEndMinutes
        case dayBatteryShowsPercentageInMenuBar
        case dayBatteryUsesWideMenuBarItem
        case taskAutoArchiveAfterIdleHours
        case doneTaskAutoArchiveAfterDays
        case archivedTaskPurgeAfterDays
        case weekPlanEntries
        case tasksPresentation
        case themeMode
        case nowPinnedJobIDs
        case nowPinnedProjectIDs
        case nowSuppressedJobIDs
        case nowSuppressedProjectIDs
        case focusCardDensity
        case newNowTaskPlacement
        case focusOverlayPresenceMode
        case focusOverlayWindowFrame
        case trainingWheelsEnabled
        case typeaheadListNavigationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try container.decode([Job].self, forKey: .jobs)
        standaloneTasks = try container.decodeIfPresent([Task].self, forKey: .standaloneTasks) ?? []
        history = try container.decode([ActivityEvent].self, forKey: .history)
        dailyCapacityMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyCapacityMinutes) ?? 540
        dayBatteryStartMinutes = try container.decodeIfPresent(Int.self, forKey: .dayBatteryStartMinutes) ?? 8 * 60
        dayBatteryEndMinutes = try container.decodeIfPresent(Int.self, forKey: .dayBatteryEndMinutes) ?? 0
        dayBatteryShowsPercentageInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .dayBatteryShowsPercentageInMenuBar) ?? true
        dayBatteryUsesWideMenuBarItem = try container.decodeIfPresent(Bool.self, forKey: .dayBatteryUsesWideMenuBarItem) ?? false
        taskAutoArchiveAfterIdleHours = try container.decodeIfPresent(Int.self, forKey: .taskAutoArchiveAfterIdleHours) ?? 0
        doneTaskAutoArchiveAfterDays = try container.decodeIfPresent(Int.self, forKey: .doneTaskAutoArchiveAfterDays) ?? 0
        archivedTaskPurgeAfterDays = try container.decodeIfPresent(Int.self, forKey: .archivedTaskPurgeAfterDays) ?? 0
        _ = try container.decodeIfPresent([LegacyWeekPlanEntry].self, forKey: .weekPlanEntries)
        tasksPresentation = try container.decodeIfPresent(TasksPresentationState.self, forKey: .tasksPresentation)
            ?? TasksPresentationState()
        themeMode = try container.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .system
        nowPinnedJobIDs = try container.decodeIfPresent([UUID].self, forKey: .nowPinnedJobIDs) ?? []
        _ = try container.decodeIfPresent([UUID].self, forKey: .nowPinnedProjectIDs)
        nowSuppressedJobIDs = try container.decodeIfPresent([UUID].self, forKey: .nowSuppressedJobIDs) ?? []
        _ = try container.decodeIfPresent([UUID].self, forKey: .nowSuppressedProjectIDs)
        focusCardDensity = try container.decodeIfPresent(FocusCardDensity.self, forKey: .focusCardDensity) ?? .standard
        newNowTaskPlacement = try container.decodeIfPresent(NewNowTaskPlacement.self, forKey: .newNowTaskPlacement) ?? .bottom
        focusOverlayPresenceMode = try container.decodeIfPresent(FocusOverlayPresenceMode.self, forKey: .focusOverlayPresenceMode)
            ?? .allDesktops
        focusOverlayWindowFrame = try container.decodeIfPresent(FocusOverlayWindowFrame.self, forKey: .focusOverlayWindowFrame)
        trainingWheelsEnabled = try container.decodeIfPresent(Bool.self, forKey: .trainingWheelsEnabled) ?? true
        typeaheadListNavigationEnabled = try container.decodeIfPresent(Bool.self, forKey: .typeaheadListNavigationEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(standaloneTasks, forKey: .standaloneTasks)
        try container.encode(history, forKey: .history)
        try container.encode(dailyCapacityMinutes, forKey: .dailyCapacityMinutes)
        try container.encode(dayBatteryStartMinutes, forKey: .dayBatteryStartMinutes)
        try container.encode(dayBatteryEndMinutes, forKey: .dayBatteryEndMinutes)
        try container.encode(dayBatteryShowsPercentageInMenuBar, forKey: .dayBatteryShowsPercentageInMenuBar)
        try container.encode(dayBatteryUsesWideMenuBarItem, forKey: .dayBatteryUsesWideMenuBarItem)
        try container.encode(taskAutoArchiveAfterIdleHours, forKey: .taskAutoArchiveAfterIdleHours)
        try container.encode(doneTaskAutoArchiveAfterDays, forKey: .doneTaskAutoArchiveAfterDays)
        try container.encode(archivedTaskPurgeAfterDays, forKey: .archivedTaskPurgeAfterDays)
        try container.encode(tasksPresentation, forKey: .tasksPresentation)
        try container.encode(themeMode, forKey: .themeMode)
        try container.encode(nowPinnedJobIDs, forKey: .nowPinnedJobIDs)
        try container.encode(nowSuppressedJobIDs, forKey: .nowSuppressedJobIDs)
        try container.encode(focusCardDensity, forKey: .focusCardDensity)
        try container.encode(newNowTaskPlacement, forKey: .newNowTaskPlacement)
        try container.encode(focusOverlayPresenceMode, forKey: .focusOverlayPresenceMode)
        try container.encodeIfPresent(focusOverlayWindowFrame, forKey: .focusOverlayWindowFrame)
        try container.encode(trainingWheelsEnabled, forKey: .trainingWheelsEnabled)
        try container.encode(typeaheadListNavigationEnabled, forKey: .typeaheadListNavigationEnabled)
    }
}

enum WorkspaceLoadOutcome {
    case loaded(WorkspaceSnapshot)
    case recoveredFromBackup(WorkspaceSnapshot)
    case noWorkspace
    case unrecoverable
}

private struct WorkspaceLocations {
    let directory: URL
    let primary: URL
    let backup: URL
}

private final class BufferedWorkspaceWriter {
    private let queue = DispatchQueue(label: "TurboTasker.workspace.persistence", qos: .utility)
    private let lock = NSLock()
    private let delay: TimeInterval

    private var generation = 0
    private var pendingSnapshot: WorkspaceSnapshot?

    init(delay: TimeInterval = 0.25) {
        self.delay = delay
    }

    func schedule(_ snapshot: WorkspaceSnapshot, write: @escaping (WorkspaceSnapshot) -> Void) {
        let generation = register(snapshot)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let snapshot = self.takePendingSnapshot(for: generation) else { return }
            write(snapshot)
        }
    }

    func saveNow(_ snapshot: WorkspaceSnapshot, write: @escaping (WorkspaceSnapshot) -> Void) {
        cancelPending()
        queue.sync {
            write(snapshot)
        }
    }

    private func register(_ snapshot: WorkspaceSnapshot) -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        pendingSnapshot = snapshot
        return generation
    }

    private func cancelPending() {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        pendingSnapshot = nil
    }

    private func takePendingSnapshot(for generation: Int) -> WorkspaceSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation else { return nil }
        let snapshot = pendingSnapshot
        pendingSnapshot = nil
        return snapshot
    }
}

enum WorkspacePersistence {
    private static let writer = BufferedWorkspaceWriter()

    static func loadOutcome() -> WorkspaceLoadOutcome {
        guard let locations = workspaceLocations() else { return .unrecoverable }

        let primaryData = try? Data(contentsOf: locations.primary)
        let backupData = try? Data(contentsOf: locations.backup)

        guard primaryData != nil || backupData != nil else {
            return .noWorkspace
        }

        if let primaryData, let snapshot = decode(primaryData) {
            return .loaded(snapshot)
        }

        if let backupData, let snapshot = decode(backupData) {
            archiveCorruptWorkspaceIfNeeded(at: locations.primary)
            writeEncodedSnapshot(snapshot, to: locations)
            return .recoveredFromBackup(snapshot)
        }

        archiveCorruptWorkspaceIfNeeded(at: locations.primary)
        archiveCorruptWorkspaceIfNeeded(at: locations.backup)
        return .unrecoverable
    }

    static func save(_ snapshot: WorkspaceSnapshot) {
        writer.schedule(snapshot) { snapshot in
            writeEncodedSnapshot(snapshot)
        }
    }

    static func saveImmediately(_ snapshot: WorkspaceSnapshot) {
        writer.saveNow(snapshot) { snapshot in
            writeEncodedSnapshot(snapshot)
        }
    }

    private static func decode(_ data: Data) -> WorkspaceSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    private static func encode(_ snapshot: WorkspaceSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    private static func writeEncodedSnapshot(_ snapshot: WorkspaceSnapshot, to locations: WorkspaceLocations? = nil) {
        guard let locations = locations ?? workspaceLocations(),
              let data = encode(snapshot) else {
            return
        }

        try? data.write(to: locations.primary, options: .atomic)
        try? data.write(to: locations.backup, options: .atomic)
    }

    private static func archiveCorruptWorkspaceIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let archivedURL = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: archivedURL)
    }

    private static func workspaceLocations() -> WorkspaceLocations? {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directoryURL = appSupportURL.appendingPathComponent("TurboTasker", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return WorkspaceLocations(
            directory: directoryURL,
            primary: directoryURL.appendingPathComponent("workspace.json"),
            backup: directoryURL.appendingPathComponent("workspace.backup.json")
        )
    }
}
