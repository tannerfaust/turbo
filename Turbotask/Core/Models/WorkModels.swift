//
//  WorkModels.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import Foundation
import SwiftUI

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

enum JobPalette: String, CaseIterable, Identifiable, Hashable, Codable {
    case forest
    case ocean
    case amber
    case rose
    case slate

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
            "Yellow"
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

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        palette: JobPalette,
        jobTasks: [Task] = [],
        projects: [Project]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.palette = palette
        self.jobTasks = jobTasks
        self.projects = projects
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case palette
        case jobTasks
        case projects
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        palette = try c.decode(JobPalette.self, forKey: .palette)
        jobTasks = try c.decodeIfPresent([Task].self, forKey: .jobTasks) ?? []
        projects = try c.decode([Project].self, forKey: .projects)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(palette, forKey: .palette)
        try c.encode(jobTasks, forKey: .jobTasks)
        try c.encode(projects, forKey: .projects)
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
    var nextAvailableAt: Date?
    /// macOS app bundle IDs for tools needed (icons only; no app control).
    var toolBundleIDs: [String]
    /// Optional plan dates (informational only; not used for scheduling).
    var startDate: Date?
    var endDate: Date?

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
        nextAvailableAt: Date? = nil,
        toolBundleIDs: [String] = [],
        startDate: Date? = nil,
        endDate: Date? = nil
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
        self.nextAvailableAt = nextAvailableAt
        self.toolBundleIDs = Task.normalizedToolBundleIDs(toolBundleIDs)
        self.startDate = startDate
        self.endDate = endDate
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
        case nextAvailableAt
        case toolBundleIDs
        case startDate
        case endDate
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
        nextAvailableAt = try container.decodeIfPresent(Date.self, forKey: .nextAvailableAt)
        toolBundleIDs = Task.normalizedToolBundleIDs(try container.decodeIfPresent([String].self, forKey: .toolBundleIDs) ?? [])
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
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
        try container.encodeIfPresent(nextAvailableAt, forKey: .nextAvailableAt)
        try container.encode(toolBundleIDs, forKey: .toolBundleIDs)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
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
            if let kpiTarget, let kpiUnit, !kpiUnit.isEmpty {
                return "KPI \(kpiTarget) \(kpiUnit)"
            }
            return "KPI"
        }
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
            "Job"
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
        case .focusRated:
            "Focus"
        case .qualityRated:
            "Quality"
        }
    }
}

struct ActivityEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var timestamp: Date
    var kind: ActivityKind
    var taskID: UUID?
    var taskTitle: String
    var projectTitle: String
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
        self.detail = detail
        self.focusRating = focusRating
        self.qualityRating = qualityRating
        self.sessionMinutes = sessionMinutes
    }
}

struct ProjectContext: Identifiable, Hashable {
    var id: UUID { project.id }
    var jobID: UUID
    var jobTitle: String
    var jobPalette: JobPalette
    var project: Project

    var jobColor: Color { jobPalette.color }
    var openTaskCount: Int { project.tasks.filter { $0.status != .done }.count }
    var doneTaskCount: Int { project.tasks.filter { $0.status == .done }.count }
    var completionPercent: Double {
        guard !project.tasks.isEmpty else { return 0 }
        return Double(doneTaskCount) / Double(project.tasks.count)
    }
}

struct TaskContext: Identifiable, Hashable {
    var id: UUID { task.id }
    /// `nil` for tasks not assigned to any job (inbox / standalone).
    var jobID: UUID?
    /// `nil` when the task sits on the job directly, not inside a project.
    var projectID: UUID?
    var jobTitle: String
    var projectTitle: String
    var jobPalette: JobPalette
    var task: Task

    var jobColor: Color { jobPalette.color }

    /// Shown in list meta lines (skips empty segments).
    var metaSubtitleParts: [String] {
        var parts: [String] = []
        if !jobTitle.isEmpty { parts.append(jobTitle) }
        if !projectTitle.isEmpty { parts.append(projectTitle) }
        if parts.isEmpty, jobID == nil, projectID == nil {
            parts.append("Inbox")
        }
        return parts
    }
}
