//
//  WorkModels.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import Foundation
import SwiftUI

enum NowListGroupingMode: String, CaseIterable, Identifiable {
    case none
    case jobs
    case jobsAndProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "Off"
        case .jobs:
            "Fields"
        case .jobsAndProjects:
            "Fields + Projects"
        }
    }

    var menuSymbol: String {
        switch self {
        case .none:
            "list.bullet"
        case .jobs:
            "briefcase"
        case .jobsAndProjects:
            "square.stack.3d.up"
        }
    }
}

enum NewNowTaskPlacement: String, CaseIterable, Identifiable, Codable {
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top:
            "Top"
        case .bottom:
            "Bottom"
        }
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

// MARK: - AI dependency & limits

enum AIDependencyProvider: String, CaseIterable, Identifiable, Hashable, Codable {
    case claude
    case codex
    case cursor
    case antigravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        }
    }

    var shortTitle: String { title }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal.fill"
        case .cursor: "cursorarrow.rays"
        case .antigravity: "arrow.triangle.2.circlepath"
        }
    }

    /// Brand-leaning accent for each assistant.
    var accent: Color {
        switch self {
        case .claude: Color(red: 0.91, green: 0.49, blue: 0.22)      // orange
        case .codex: Color(red: 0.52, green: 0.45, blue: 0.96)       // blue / purple
        case .cursor: Color(red: 0.62, green: 0.64, blue: 0.70)      // neutral
        case .antigravity: Color(red: 0.20, green: 0.70, blue: 0.74) // green / blue
        }
    }

    /// Candidate desktop-app bundle IDs in priority order; the first installed one
    /// supplies the real app icon (falls back to `symbol` when none is present).
    var bundleIdentifiers: [String] {
        switch self {
        case .claude: ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .codex: ["com.openai.codex"]
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        case .antigravity: ["com.google.antigravity"]
        }
    }
}

struct AILimitSchedule: Hashable, Codable, Equatable {
    var resetHour: Int
    var resetMinute: Int
    /// Calendar weekday indices (1 = Sunday … 7 = Saturday). Empty means every day.
    var resetWeekdays: [Int]

    init(resetHour: Int = 9, resetMinute: Int = 0, resetWeekdays: [Int] = []) {
        self.resetHour = min(23, max(0, resetHour))
        self.resetMinute = min(59, max(0, resetMinute))
        self.resetWeekdays = resetWeekdays
    }

    func nextReset(after date: Date = .now, calendar: Calendar = .current) -> Date {
        let activeWeekdays = effectiveWeekdays
        let startDay = calendar.startOfDay(for: date)

        for dayOffset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard activeWeekdays.contains(weekday) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = resetHour
            components.minute = resetMinute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { continue }
            if candidate > date { return candidate }
        }

        return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    }

    func resetTimeLabel(calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = resetHour
        components.minute = resetMinute
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", resetHour, resetMinute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    func weekdaySummary(calendar: Calendar = .current) -> String {
        let active = effectiveWeekdays.sorted()
        if active.count == 7 { return "Every day" }
        let symbols = calendar.shortWeekdaySymbols
        let labels = active.compactMap { weekday -> String? in
            guard weekday >= 1, weekday <= symbols.count else { return nil }
            return String(symbols[weekday - 1].prefix(1))
        }
        return labels.joined(separator: " · ")
    }

    private var effectiveWeekdays: Set<Int> {
        if resetWeekdays.isEmpty { return Set(1...7) }
        return Set(resetWeekdays.filter { (1...7).contains($0) })
    }
}

enum JobPalette: String, CaseIterable, Identifiable, Hashable, Codable {
    case forest
    case ocean
    case amber
    case rose
    case slate
    case violet
    case magenta
    case mint
    case teal
    case sky
    case indigo
    case lime
    case coral
    case plum
    case copper
    case cyan
    case iris
    case grey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest:
            "Green"
        case .ocean:
            "Blue"
        case .amber:
            "Orange"
        case .rose:
            "Red"
        case .slate:
            "Gold"
        case .violet:
            "Violet"
        case .magenta:
            "Magenta"
        case .mint:
            "Mint"
        case .teal:
            "Teal"
        case .sky:
            "Sky"
        case .indigo:
            "Indigo"
        case .lime:
            "Lime"
        case .coral:
            "Coral"
        case .plum:
            "Plum"
        case .copper:
            "Copper"
        case .cyan:
            "Cyan"
        case .iris:
            "Iris"
        case .grey:
            "Grey"
        }
    }

    var color: Color {
        switch self {
        case .forest:
            Color(red: 0.05, green: 0.78, blue: 0.42)
        case .ocean:
            Color(red: 0.08, green: 0.48, blue: 1.0)
        case .amber:
            Color(red: 1.0, green: 0.48, blue: 0.06)
        case .rose:
            Color(red: 0.96, green: 0.18, blue: 0.28)
        case .slate:
            Color(red: 0.98, green: 0.82, blue: 0.06)
        case .violet:
            Color(red: 0.55, green: 0.28, blue: 0.98)
        case .magenta:
            Color(red: 0.92, green: 0.20, blue: 0.72)
        case .mint:
            Color(red: 0.10, green: 0.82, blue: 0.62)
        case .teal:
            Color(red: 0.0, green: 0.62, blue: 0.58)
        case .sky:
            Color(red: 0.22, green: 0.72, blue: 0.98)
        case .indigo:
            Color(red: 0.29, green: 0.28, blue: 0.92)
        case .lime:
            Color(red: 0.58, green: 0.86, blue: 0.12)
        case .coral:
            Color(red: 1.0, green: 0.42, blue: 0.38)
        case .plum:
            Color(red: 0.60, green: 0.22, blue: 0.62)
        case .copper:
            Color(red: 0.78, green: 0.42, blue: 0.22)
        case .cyan:
            Color(red: 0.0, green: 0.76, blue: 0.92)
        case .iris:
            Color(red: 0.40, green: 0.50, blue: 1.0)
        case .grey:
            Color(red: 0.52, green: 0.52, blue: 0.56)
        }
    }
}

struct Job: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var summary: String
    var palette: JobPalette
    /// Tasks on this job that are not inside any project.
    var jobTasks: [Task]
    var projects: [Project]
    var operations: [Operation]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        palette: JobPalette,
        jobTasks: [Task] = [],
        projects: [Project],
        operations: [Operation] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.palette = palette
        self.jobTasks = jobTasks
        self.projects = projects
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case palette
        case jobTasks
        case projects
        case operations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        palette = try c.decode(JobPalette.self, forKey: .palette)
        jobTasks = try c.decodeIfPresent([Task].self, forKey: .jobTasks) ?? []
        projects = try c.decode([Project].self, forKey: .projects)
        operations = try c.decodeIfPresent([Operation].self, forKey: .operations) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(palette, forKey: .palette)
        try c.encode(jobTasks, forKey: .jobTasks)
        try c.encode(projects, forKey: .projects)
        try c.encode(operations, forKey: .operations)
    }
}

/// An ongoing responsibility within a field. Unlike a project it has no outcome or completion state.
struct Operation: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var summary: String
    var isArchived: Bool
    var archivedAt: Date?
    var tasks: [Task]
    /// Tasks newly archived by the most recent operation archive action.
    var cascadeArchivedTaskIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        tasks: [Task] = [],
        cascadeArchivedTaskIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.tasks = tasks
        self.cascadeArchivedTaskIDs = cascadeArchivedTaskIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, isArchived, archivedAt, tasks, cascadeArchivedTaskIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        tasks = try c.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        cascadeArchivedTaskIDs = try c.decodeIfPresent([UUID].self, forKey: .cascadeArchivedTaskIDs) ?? []
    }
}

struct Project: Identifiable, Hashable {
    let id: UUID
    var title: String
    var outcome: String
    /// Single emoji shown next to the project name (user-picked).
    var iconEmoji: String
    var tasks: [Task]

    init(
        id: UUID = UUID(),
        title: String,
        outcome: String,
        tasks: [Task],
        iconEmoji: String = ""
    ) {
        self.id = id
        self.title = title
        self.outcome = outcome
        self.tasks = tasks
        self.iconEmoji = Self.normalizedIconEmoji(iconEmoji)
    }

    /// Title with leading emoji when set (for lists, task context, pickers).
    var displayTitle: String {
        iconEmoji.isEmpty ? title : "\(iconEmoji) \(title)"
    }

    static func normalizedIconEmoji(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return String(first)
    }
}

extension Project: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case outcome
        case tasks
        case iconEmoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        outcome = try c.decode(String.self, forKey: .outcome)
        tasks = try c.decode([Task].self, forKey: .tasks)
        iconEmoji = Self.normalizedIconEmoji(try c.decodeIfPresent(String.self, forKey: .iconEmoji) ?? "")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(iconEmoji, forKey: .iconEmoji)
    }
}

struct TaskSubtask: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

struct Task: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var summary: String
    var why: String
    var energy: TaskEnergy
    var cadence: TaskCadence
    var status: TaskStatus
    var progress: Double
    var estimatedMinutes: Int
    var isScheduledNow: Bool
    var nowOrder: Double
    var priority: Int
    var waitingOn: String?
    var nextStep: String
    var repeatEveryMinutes: Int?
    var kpiTarget: Int?
    var kpiUnit: String?
    var kpiRoundsRemaining: Int?
    var kpiCount: Int
    var nextAvailableAt: Date?
    /// macOS app bundle IDs for tools needed (icons only; no app control).
    var toolBundleIDs: [String]
    /// Optional plan dates (informational only; not used for scheduling).
    var startDate: Date?
    var endDate: Date?
    /// Hidden from Now, registry, and job/project lists until restored (e.g. auto-archived when idle).
    var isArchived: Bool
    /// When the task was archived; used for retention purge. Nil for legacy data until migration fills it.
    var archivedAt: Date?
    /// Task IDs that must reach Done before this task can start.
    var blockedByTaskIDs: [UUID]
    /// Small checklist items that live inside the parent task.
    var subtasks: [TaskSubtask]
    /// When set, this task depends on a specific AI tool/model quota.
    var aiProvider: AIDependencyProvider?
    /// Status to restore when an AI limit hold ends.
    var aiLimitResumeStatus: TaskStatus?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        why: String,
        energy: TaskEnergy,
        cadence: TaskCadence = .oneOff,
        status: TaskStatus,
        progress: Double,
        estimatedMinutes: Int,
        isScheduledNow: Bool,
        nowOrder: Double = 0,
        priority: Int,
        waitingOn: String? = nil,
        nextStep: String,
        repeatEveryMinutes: Int? = nil,
        kpiTarget: Int? = nil,
        kpiUnit: String? = nil,
        kpiRoundsRemaining: Int? = nil,
        kpiCount: Int = 0,
        nextAvailableAt: Date? = nil,
        toolBundleIDs: [String] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        blockedByTaskIDs: [UUID] = [],
        subtasks: [TaskSubtask] = [],
        aiProvider: AIDependencyProvider? = nil,
        aiLimitResumeStatus: TaskStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.why = why
        self.energy = energy
        self.cadence = cadence
        self.status = status
        self.progress = progress
        self.estimatedMinutes = estimatedMinutes
        self.isScheduledNow = isScheduledNow
        self.nowOrder = nowOrder
        self.priority = priority
        self.waitingOn = waitingOn
        self.nextStep = nextStep
        self.repeatEveryMinutes = repeatEveryMinutes
        self.kpiTarget = kpiTarget
        self.kpiUnit = kpiUnit
        self.kpiRoundsRemaining = kpiRoundsRemaining
        self.kpiCount = kpiCount
        self.nextAvailableAt = nextAvailableAt
        self.toolBundleIDs = Task.normalizedToolBundleIDs(toolBundleIDs)
        self.startDate = startDate
        self.endDate = endDate
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(blockedByTaskIDs, for: id)
        self.subtasks = Task.normalizedSubtasks(subtasks)
        self.aiProvider = aiProvider
        self.aiLimitResumeStatus = aiLimitResumeStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case why
        case energy
        case cadence
        case status
        case progress
        case estimatedMinutes
        case isScheduledNow
        case isScheduledToday
        case nowOrder
        case priority
        case waitingOn
        case nextStep
        case repeatEveryMinutes
        case kpiTarget
        case kpiUnit
        case kpiRoundsRemaining
        case kpiCount
        case nextAvailableAt
        case toolBundleIDs
        case startDate
        case endDate
        case isArchived
        case archivedAt
        case blockedByTaskIDs
        case subtasks
        case aiProvider
        case aiLimitResumeStatus
    }

    static let maxDependenciesPerTask = 24
    static let maxSubtasksPerTask = 24

    static func normalizedBlockedByTaskIDs(_ raw: [UUID], for taskID: UUID) -> [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for id in raw where id != taskID {
            guard seen.insert(id).inserted else { continue }
            out.append(id)
            if out.count >= maxDependenciesPerTask { break }
        }
        return out
    }

    static func normalizedToolBundleIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in raw {
            let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t).inserted else { continue }
            out.append(t)
            if out.count >= Task.maxToolAppsPerTask { break }
        }
        return out
    }

    static func normalizedSubtasks(_ raw: [TaskSubtask]) -> [TaskSubtask] {
        var seen = Set<UUID>()
        var out: [TaskSubtask] = []
        for item in raw {
            let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(item.id).inserted else { continue }
            out.append(TaskSubtask(id: item.id, title: trimmed, isDone: item.isDone))
            if out.count >= maxSubtasksPerTask { break }
        }
        return out
    }

    static let maxToolAppsPerTask = 12

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        why = try container.decode(String.self, forKey: .why)
        energy = try container.decode(TaskEnergy.self, forKey: .energy)
        cadence = try container.decodeIfPresent(TaskCadence.self, forKey: .cadence) ?? .oneOff
        status = try container.decode(TaskStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        estimatedMinutes = try container.decode(Int.self, forKey: .estimatedMinutes)
        isScheduledNow = try container.decodeIfPresent(Bool.self, forKey: .isScheduledNow)
            ?? container.decodeIfPresent(Bool.self, forKey: .isScheduledToday)
            ?? false
        priority = try container.decode(Int.self, forKey: .priority)
        nowOrder = try container.decodeIfPresent(Double.self, forKey: .nowOrder) ?? Double(100 - priority)
        waitingOn = try container.decodeIfPresent(String.self, forKey: .waitingOn)
        nextStep = try container.decode(String.self, forKey: .nextStep)
        repeatEveryMinutes = try container.decodeIfPresent(Int.self, forKey: .repeatEveryMinutes)
        kpiTarget = try container.decodeIfPresent(Int.self, forKey: .kpiTarget)
        kpiUnit = try container.decodeIfPresent(String.self, forKey: .kpiUnit)
        kpiRoundsRemaining = try container.decodeIfPresent(Int.self, forKey: .kpiRoundsRemaining)
        kpiCount = try container.decodeIfPresent(Int.self, forKey: .kpiCount) ?? 0
        nextAvailableAt = try container.decodeIfPresent(Date.self, forKey: .nextAvailableAt)
        toolBundleIDs = Task.normalizedToolBundleIDs(try container.decodeIfPresent([String].self, forKey: .toolBundleIDs) ?? [])
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(
            try container.decodeIfPresent([UUID].self, forKey: .blockedByTaskIDs) ?? [],
            for: id
        )
        subtasks = Task.normalizedSubtasks(try container.decodeIfPresent([TaskSubtask].self, forKey: .subtasks) ?? [])
        aiProvider = try container.decodeIfPresent(AIDependencyProvider.self, forKey: .aiProvider)
        aiLimitResumeStatus = try container.decodeIfPresent(TaskStatus.self, forKey: .aiLimitResumeStatus)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(why, forKey: .why)
        try container.encode(energy, forKey: .energy)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encode(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encode(isScheduledNow, forKey: .isScheduledNow)
        try container.encode(nowOrder, forKey: .nowOrder)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(waitingOn, forKey: .waitingOn)
        try container.encode(nextStep, forKey: .nextStep)
        try container.encodeIfPresent(repeatEveryMinutes, forKey: .repeatEveryMinutes)
        try container.encodeIfPresent(kpiTarget, forKey: .kpiTarget)
        try container.encodeIfPresent(kpiUnit, forKey: .kpiUnit)
        try container.encodeIfPresent(kpiRoundsRemaining, forKey: .kpiRoundsRemaining)
        try container.encode(kpiCount, forKey: .kpiCount)
        try container.encodeIfPresent(nextAvailableAt, forKey: .nextAvailableAt)
        try container.encode(toolBundleIDs, forKey: .toolBundleIDs)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encode(blockedByTaskIDs, forKey: .blockedByTaskIDs)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encodeIfPresent(aiProvider, forKey: .aiProvider)
        try container.encodeIfPresent(aiLimitResumeStatus, forKey: .aiLimitResumeStatus)
    }

    /// Copies every mutable field from `other` onto `self` (same `id` required). Used for ⌘Z undo.
    mutating func applyFullState(from other: Task) {
        guard id == other.id else { return }
        title = other.title
        summary = other.summary
        why = other.why
        energy = other.energy
        cadence = other.cadence
        status = other.status
        progress = other.progress
        estimatedMinutes = other.estimatedMinutes
        isScheduledNow = other.isScheduledNow
        nowOrder = other.nowOrder
        priority = other.priority
        waitingOn = other.waitingOn
        nextStep = other.nextStep
        repeatEveryMinutes = other.repeatEveryMinutes
        kpiTarget = other.kpiTarget
        kpiUnit = other.kpiUnit
        kpiRoundsRemaining = other.kpiRoundsRemaining
        kpiCount = other.kpiCount
        nextAvailableAt = other.nextAvailableAt
        toolBundleIDs = other.toolBundleIDs
        startDate = other.startDate
        endDate = other.endDate
        isArchived = other.isArchived
        archivedAt = other.archivedAt
        blockedByTaskIDs = other.blockedByTaskIDs
        subtasks = other.subtasks
        aiProvider = other.aiProvider
        aiLimitResumeStatus = other.aiLimitResumeStatus
    }

    /// `true` when the task is not done and the calendar day is past the end date.
    var isEndDateOverdue: Bool {
        guard let endDate, status != .done else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: Date()) > cal.startOfDay(for: endDate)
    }

    var isAvailableNow: Bool {
        nextAvailableAt == nil || nextAvailableAt ?? .distantPast <= .now
    }

    var cadenceBadge: String? {
        switch cadence {
        case .oneOff:
            return nil
        case .repeatable:
            return "Repeatable"
        case .kpi:
            var parts: [String] = []
            if let label = kpiCounterLabel {
                parts.append(label)
            }
            if let rounds = kpiRoundsLabel {
                parts.append(rounds)
            }
            return parts.isEmpty ? "Counted" : parts.joined(separator: " · ")
        }
    }

    var kpiCounterLabel: String? {
        guard cadence == .kpi, let target = kpiTarget else { return nil }
        return "\(kpiCount)/\(target)"
    }

    var kpiRoundsLabel: String? {
        guard cadence == .kpi, let rounds = kpiRoundsRemaining else { return nil }
        if rounds == 0, status != .done {
            return "Final round"
        }
        guard rounds > 0 else { return nil }
        return rounds == 1 ? "1 round left" : "\(rounds) rounds left"
    }
}

enum TaskEnergy: String, CaseIterable, Identifiable, Hashable, Codable {
    case deepFocus
    case shallowWork
    case multitask2
    case multitask3
    case multitask4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepFocus:
            "Deep Focus"
        case .shallowWork:
            "Shallow Work"
        case .multitask2:
            "Multitaskable 2"
        case .multitask3:
            "Multitaskable 3"
        case .multitask4:
            "Multitaskable 4"
        }
    }

    var guidance: String {
        switch self {
        case .deepFocus:
            "Single-threaded work."
        case .shallowWork:
            "Light work, one thing at a time."
        case .multitask2:
            "Up to 2 tasks at once in a parallel bundle (this task + 1 other)."
        case .multitask3:
            "Up to 3 tasks at once in a parallel bundle."
        case .multitask4:
            "Up to 4 tasks at once in a parallel bundle."
        }
    }

    var shortTitle: String {
        switch self {
        case .deepFocus:
            "Deep"
        case .shallowWork:
            "Shallow"
        case .multitask2:
            "MT-2"
        case .multitask3:
            "MT-3"
        case .multitask4:
            "MT-4"
        }
    }

    /// Maximum tasks that may run together in one parallel group (matches MT-n).
    var maxParallelGroupSize: Int {
        switch self {
        case .deepFocus, .shallowWork:
            1
        case .multitask2:
            2
        case .multitask3:
            3
        case .multitask4:
            4
        }
    }

    /// How many *other* tasks this mode allows beside itself (`maxParallelGroupSize - 1`).
    var companionCapacity: Int {
        max(0, maxParallelGroupSize - 1)
    }

    var defaultParallelCapacity: Int {
        maxParallelGroupSize
    }

    var isMultitaskable: Bool {
        maxParallelGroupSize > 1
    }

    /// Smallest MT-n that allows `count` tasks in one parallel bundle (2 → MT-2 … 4 → MT-4).
    static func multitaskEnergy(forParallelBundleCount count: Int) -> TaskEnergy? {
        switch count {
        case 2:
            .multitask2
        case 3:
            .multitask3
        case 4:
            .multitask4
        default:
            nil
        }
    }

    var accent: Color {
        switch self {
        case .deepFocus:
            Color(red: 0.12, green: 0.38, blue: 1.0)
        case .shallowWork:
            Color(red: 0.98, green: 0.72, blue: 0.08)
        case .multitask2:
            Color(red: 0.0, green: 0.82, blue: 0.88)
        case .multitask3:
            Color(red: 0.94, green: 0.22, blue: 0.62)
        case .multitask4:
            Color(red: 0.45, green: 0.92, blue: 0.18)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.multitask4.rawValue:
            self = .multitask4
        case Self.multitask3.rawValue:
            self = .multitask3
        case Self.multitask2.rawValue, "multitask", "asyncOrbit":
            self = .multitask2
        case Self.shallowWork.rawValue, "shallowSprint":
            self = .shallowWork
        default:
            self = .deepFocus
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TaskCadence: String, CaseIterable, Identifiable, Hashable, Codable {
    case oneOff
    case repeatable
    case kpi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneOff:
            "One-Off"
        case .repeatable:
            "Repeatable"
        case .kpi:
            "KPI"
        }
    }

    var accent: Color {
        switch self {
        case .oneOff:
            TurboTheme.slate
        case .repeatable:
            TurboTheme.slate
        case .kpi:
            TurboTheme.warning
        }
    }
}

enum TaskStatus: String, CaseIterable, Identifiable, Hashable, Codable {
    case queued
    case active
    case waiting
    case paused
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queued:
            "Not Started"
        case .active:
            "In Progress"
        case .waiting:
            "Waiting"
        case .paused:
            "Paused"
        case .done:
            "Done"
        }
    }

    var accent: Color {
        switch self {
        case .queued:
            Color(red: 0.48, green: 0.52, blue: 0.62)
        case .active:
            Color(red: 0.02, green: 0.82, blue: 0.45)
        case .waiting:
            Color(red: 0.12, green: 0.58, blue: 1.0)
        case .paused:
            Color(red: 1.0, green: 0.52, blue: 0.08)
        case .done:
            Color(red: 0.0, green: 0.70, blue: 0.64)
        }
    }

    var menuSymbol: String {
        switch self {
        case .queued:
            "circle"
        case .active:
            "play.fill"
        case .waiting:
            "hourglass"
        case .paused:
            "pause.fill"
        case .done:
            "checkmark.circle.fill"
        }
    }
}

enum TaskViewMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case table
    case kanban
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table:
            "Table"
        case .kanban:
            "Kanban"
        case .cards:
            "Cards"
        }
    }

    var symbol: String {
        switch self {
        case .table:
            "tablecells"
        case .kanban:
            "square.grid.3x2"
        case .cards:
            "rectangle.grid.2x2"
        }
    }
}

enum TaskVisibleField: String, CaseIterable, Identifiable, Hashable, Codable {
    case project
    case job
    case status
    case energy
    case priority
    case estimate
    case progress
    case now
    case nextStep
    case waitingOn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project:
            "Project"
        case .job:
            "Field"
        case .status:
            "Status"
        case .energy:
            "Mode"
        case .priority:
            "Priority"
        case .estimate:
            "Estimate"
        case .progress:
            "Progress"
        case .now:
            "Now"
        case .nextStep:
            "Next Step"
        case .waitingOn:
            "Waiting On"
        }
    }
}

struct TasksPresentationState: Hashable, Codable {
    var viewMode: TaskViewMode
    var visibleFields: Set<TaskVisibleField>

    init(
        viewMode: TaskViewMode = .table,
        visibleFields: Set<TaskVisibleField> = Self.defaultVisibleFields
    ) {
        self.viewMode = viewMode
        self.visibleFields = visibleFields
    }

    static let defaultVisibleFields: Set<TaskVisibleField> = [
        .project,
        .status,
        .energy,
        .priority,
        .estimate,
        .progress,
        .now,
        .nextStep
    ]

    enum CodingKeys: String, CodingKey {
        case viewMode
        case visibleFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewMode = try container.decodeIfPresent(TaskViewMode.self, forKey: .viewMode) ?? .table
        if let raw = try container.decodeIfPresent([String].self, forKey: .visibleFields) {
            let parsed = Set(raw.compactMap { TaskVisibleField(rawValue: $0) })
            visibleFields = parsed.isEmpty ? Self.defaultVisibleFields : parsed
        } else {
            visibleFields = Self.defaultVisibleFields
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewMode, forKey: .viewMode)
        try container.encode(visibleFields.map(\.rawValue).sorted(), forKey: .visibleFields)
    }
}

enum ActivityKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case started
    case paused
    case waiting
    case completed
    case switched
    case counted
    case focusRated
    case qualityRated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .started:
            "Started"
        case .paused:
            "Paused"
        case .waiting:
            "Waiting"
        case .completed:
            "Completed"
        case .switched:
            "Switched"
        case .counted:
            "Counted"
        case .focusRated:
            "Focus"
        case .qualityRated:
            "Quality"
        }
    }
}

struct ActivityEvent: Identifiable, Hashable, Codable {
    enum ContainerKind: String, Hashable, Codable { case project, operation }
    let id: UUID
    var timestamp: Date
    var kind: ActivityKind
    var taskID: UUID?
    var taskTitle: String
    var projectTitle: String
    var containerKind: ContainerKind?
    var containerTitle: String
    var detail: String
    var focusRating: Int?
    var qualityRating: Int?
    var sessionMinutes: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: ActivityKind,
        taskID: UUID?,
        taskTitle: String,
        projectTitle: String,
        containerKind: ContainerKind? = nil,
        containerTitle: String? = nil,
        detail: String,
        focusRating: Int? = nil,
        qualityRating: Int? = nil,
        sessionMinutes: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.projectTitle = projectTitle
        self.containerKind = containerKind ?? (projectTitle.isEmpty ? nil : .project)
        self.containerTitle = containerTitle ?? projectTitle
        self.detail = detail
        self.focusRating = focusRating
        self.qualityRating = qualityRating
        self.sessionMinutes = sessionMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, taskID, taskTitle, projectTitle, containerKind, containerTitle
        case detail, focusRating, qualityRating, sessionMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        kind = try c.decode(ActivityKind.self, forKey: .kind)
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        taskTitle = try c.decode(String.self, forKey: .taskTitle)
        projectTitle = try c.decodeIfPresent(String.self, forKey: .projectTitle) ?? ""
        containerKind = try c.decodeIfPresent(ContainerKind.self, forKey: .containerKind)
            ?? (projectTitle.isEmpty ? nil : .project)
        containerTitle = try c.decodeIfPresent(String.self, forKey: .containerTitle) ?? projectTitle
        detail = try c.decode(String.self, forKey: .detail)
        focusRating = try c.decodeIfPresent(Int.self, forKey: .focusRating)
        qualityRating = try c.decodeIfPresent(Int.self, forKey: .qualityRating)
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes)
    }
}

struct ProjectContext: Identifiable, Hashable {
    var id: UUID { project.id }
    var jobID: UUID
    var jobTitle: String
    var jobPalette: JobPalette
    var project: Project

    var jobColor: Color {
        jobPalette.color
    }
    var openTaskCount: Int { project.tasks.filter { !$0.isArchived && $0.status != .done }.count }
    var doneTaskCount: Int { project.tasks.filter { $0.status == .done }.count }
    var completionPercent: Double {
        guard !project.tasks.isEmpty else { return 0 }
        return Double(doneTaskCount) / Double(project.tasks.count)
    }
}

struct OperationContext: Identifiable, Hashable {
    var id: UUID { operation.id }
    var jobID: UUID
    var jobTitle: String
    var jobPalette: JobPalette
    var operation: Operation

    var jobColor: Color { jobPalette.color }
    var openTaskCount: Int { operation.tasks.filter { !$0.isArchived && $0.status != .done }.count }
}

struct TaskContext: Identifiable, Hashable {
    var id: UUID { task.id }
    /// `nil` for tasks not assigned to any job (inbox / standalone).
    var jobID: UUID?
    /// `nil` when the task sits on the job directly, not inside a project.
    var projectID: UUID?
    /// `nil` unless the task belongs to an ongoing operation. Mutually exclusive with `projectID`.
    var operationID: UUID? = nil
    var jobTitle: String
    var projectTitle: String
    var operationTitle: String = ""
    var jobPalette: JobPalette
    var task: Task

    var jobColor: Color {
        jobID == nil ? TurboTheme.inboxAccent : jobPalette.color
    }

    /// Shown in list meta lines (skips empty segments).
    var metaSubtitleParts: [String] {
        var parts: [String] = []
        if !jobTitle.isEmpty { parts.append(jobTitle) }
        if !projectTitle.isEmpty { parts.append(projectTitle) }
        if !operationTitle.isEmpty { parts.append(operationTitle) }
        if parts.isEmpty, jobID == nil, projectID == nil {
            parts.append("Inbox")
        }
        return parts
    }

    var containerTitle: String { projectTitle.isEmpty ? operationTitle : projectTitle }
    var isOperationTask: Bool { operationID != nil }
}
