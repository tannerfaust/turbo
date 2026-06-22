//
//  TaskEditorDialog.swift
//  Turbotask
//
//  Shared task editor sheet (Now, Portfolio, Jobs, Registry, Focus overlay).
//

import SwiftUI

struct TaskEditorDialog: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext

    @State private var title: String
    @State private var energy: TaskEnergy
    @State private var cadence: TaskCadence
    @State private var status: TaskStatus
    @State private var isScheduledNow: Bool
    @State private var isArchived: Bool
    @State private var repeatEveryMinutes: Int
    @State private var hasRepeatDelay: Bool
    @State private var kpiTarget: Int
    @State private var hasKpiRounds: Bool
    @State private var kpiRoundsRemaining: Int
    @State private var kpiCount: Int
    @State private var toolBundleIDs: [String]
    @State private var selectedJobID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var selectedOperationID: UUID?
    @State private var toolsPickerOpen = false
    @State private var hasStartDate: Bool
    @State private var hasEndDate: Bool
    @State private var planStart = Date()
    @State private var planEnd = Date()
    @State private var blockedByTaskIDs: [UUID]

    init(context: TaskContext) {
        self.context = context
        _title = State(initialValue: context.task.title)
        _energy = State(initialValue: context.task.energy)
        _cadence = State(initialValue: context.task.cadence)
        _status = State(initialValue: context.task.status)
        _isScheduledNow = State(initialValue: context.task.isScheduledNow)
        _isArchived = State(initialValue: context.task.isArchived)
        _repeatEveryMinutes = State(initialValue: context.task.repeatEveryMinutes ?? 60)
        _hasRepeatDelay = State(initialValue: context.task.repeatEveryMinutes != nil)
        _kpiTarget = State(initialValue: context.task.kpiTarget ?? 10)
        _hasKpiRounds = State(initialValue: context.task.kpiRoundsRemaining != nil)
        _kpiRoundsRemaining = State(initialValue: context.task.kpiRoundsRemaining ?? 1)
        _kpiCount = State(initialValue: context.task.kpiCount)
        _toolBundleIDs = State(initialValue: context.task.toolBundleIDs)
        _selectedJobID = State(initialValue: context.jobID)
        _selectedProjectID = State(initialValue: context.projectID)
        _selectedOperationID = State(initialValue: context.operationID)
        _hasStartDate = State(initialValue: context.task.startDate != nil)
        _hasEndDate = State(initialValue: context.task.endDate != nil)
        _planStart = State(initialValue: context.task.startDate ?? Date())
        _planEnd = State(initialValue: context.task.endDate ?? Date())
        _blockedByTaskIDs = State(initialValue: context.task.blockedByTaskIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit Task")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(TurboTheme.ink)
                Text(locationSummary)
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            .padding(24)

            Divider()

            Form {
                if !store.jobs.isEmpty {
                    Section("Location") {
                        Picker("Field", selection: $selectedJobID) {
                            Text("Inbox (no field)").tag(nil as UUID?)
                            ForEach(store.jobs) { job in
                                Text(job.title).tag(Optional(job.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if selectedJobID != nil {
                            Picker("Project", selection: $selectedProjectID) {
                                Text("None — task on field only").tag(nil as UUID?)
                                ForEach(availableProjects) { project in
                                    Text(project.project.displayTitle).tag(Optional(project.project.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Operation", selection: $selectedOperationID) {
                                Text("None").tag(nil as UUID?)
                                ForEach(availableOperations) { operation in
                                    Text(operation.operation.title).tag(Optional(operation.operation.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                Section("Task") {
                    TextField("Title", text: $title)
                }

                Section("Tools needed") {
                    VStack(spacing: 14) {
                        HStack {
                            Spacer(minLength: 0)
                            TaskToolsIconRow(bundleIDs: toolBundleIDs, iconSize: 28, maxIcons: 8)
                            Spacer(minLength: 0)
                        }
                        HStack {
                            Spacer(minLength: 0)
                            Button("Choose apps…") {
                                toolsPickerOpen = true
                            }
                            .buttonStyle(.bordered)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                }

                Section("Behavior") {
                    HStack(alignment: .center, spacing: 14) {
                        Text("Status")
                            .font(.body)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .frame(width: 76, alignment: .leading)
                        Picker("", selection: $status) {
                            ForEach(TaskStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .controlSize(.regular)
                        .accessibilityLabel("Status")
                    }
                    .frame(minHeight: 28)

                    HStack(alignment: .center, spacing: 14) {
                        Text("Type")
                            .font(.body)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .frame(width: 76, alignment: .leading)
                        Picker("", selection: $energy) {
                            ForEach(TaskEnergy.allCases) { energy in
                                Text(energy.title).tag(energy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .controlSize(.regular)
                        .accessibilityLabel("Work mode type")
                    }
                    .frame(minHeight: 28)

                    HStack(alignment: .center, spacing: 14) {
                        Text("Pattern")
                            .font(.body)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .frame(width: 76, alignment: .leading)
                        Picker("", selection: $cadence) {
                            ForEach(TaskCadence.allCases) { cadence in
                                Text(cadence.title).tag(cadence)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .controlSize(.regular)
                        .accessibilityLabel("Task pattern")
                    }
                    .frame(minHeight: 28)

                    Toggle("Show in Now", isOn: $isScheduledNow)
                        .trainingWheelsTooltip("Toggle Now scheduling · ⌥⌘B")

                    Toggle("Archived (hidden from Now and field lists)", isOn: $isArchived)
                        .trainingWheelsTooltip("Archive hides the task from active lists")
                }

                Section {
                    Toggle("Start date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Starts", selection: $planStart, displayedComponents: .date)
                    }
                    Toggle("Target end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $planEnd, displayedComponents: .date)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Plan")
                        TurboInfoButton(
                            title: "Plan dates",
                            message: "These dates are informational. They help with planning and overdue visibility, but they do not drive the task state."
                        )
                    }
                }

                Section {
                    if blockedByTaskIDs.isEmpty {
                        Text("No prerequisites. This task can start anytime.")
                            .font(.subheadline)
                            .foregroundStyle(TurboTheme.mutedInk)
                    } else {
                        ForEach(blockedByTaskIDs, id: \.self) { blockerID in
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.52, green: 0.38, blue: 0.96))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(blockerTitle(for: blockerID))
                                        .font(.subheadline.weight(.medium))
                                    Text(blockerMeta(for: blockerID))
                                        .font(.caption)
                                        .foregroundStyle(TurboTheme.mutedInk)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    blockedByTaskIDs.removeAll { $0 == blockerID }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(TurboTheme.mutedInk)
                                }
                                .buttonStyle(.plain)
                                .help("Remove prerequisite")
                            }
                        }
                    }

                    Menu {
                        if dependencyCandidates.isEmpty {
                            Text("No other tasks available")
                        } else {
                            ForEach(dependencyCandidates) { candidate in
                                Button {
                                    blockedByTaskIDs.append(candidate.task.id)
                                    blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(blockedByTaskIDs, for: context.task.id)
                                } label: {
                                    Text(candidate.task.title)
                                }
                            }
                        }
                    } label: {
                        Label("Add prerequisite…", systemImage: "link.badge.plus")
                    }
                    .disabled(dependencyCandidates.isEmpty)
                } header: {
                    HStack(spacing: 6) {
                        Text("Starts after")
                        TurboInfoButton(
                            title: "Task dependencies",
                            message: "Linked tasks stay in Not Started until every prerequisite is Done. When the last blocker finishes, follow-ups move to In Progress automatically."
                        )
                    }
                } footer: {
                    Text("In Kanban, hold Option and drop one card onto another to link them the same way.")
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)
                }

                if cadence == .repeatable {
                    Section("Repeat") {
                        Stepper("Reappear After: \(repeatEveryMinutes) min", value: $repeatEveryMinutes, in: 15...2880, step: 15)
                    }
                }

                if cadence == .kpi {
                    Section("Counted Task") {
                        Stepper("Amount: \(kpiTarget)", value: $kpiTarget, in: 1...500, step: 1)
                        Toggle("Use rounds", isOn: $hasKpiRounds)
                        if hasKpiRounds {
                            Stepper("Rounds left: \(kpiRoundsRemaining)", value: $kpiRoundsRemaining, in: 1...50, step: 1)
                        }
                        Toggle("Reappear timer", isOn: $hasRepeatDelay)
                        if hasRepeatDelay {
                            Stepper("Reappear after: \(repeatEveryMinutes) min", value: $repeatEveryMinutes, in: 15...2880, step: 15)
                        }
                        Stepper("Current count: \(kpiCount)", value: $kpiCount, in: 0...10_000, step: 1)
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $toolsPickerOpen) {
                TaskToolsPickerSheet(bundleIDs: $toolBundleIDs)
                    .environmentObject(store)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .trainingWheelsTooltip("Discard changes · Esc")

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .trainingWheelsTooltip("Save task · Return")
            }
            .padding(24)
        }
        .background(TurboTheme.backgroundRaised)
        .onAppear {
            syncProjectSelection()
        }
        .onChange(of: selectedJobID) {
            syncProjectSelection()
        }
        .onChange(of: selectedProjectID) { _, value in
            if value != nil { selectedOperationID = nil }
        }
        .onChange(of: selectedOperationID) { _, value in
            if value != nil { selectedProjectID = nil }
        }
    }

    private func save() {
        guard let live = store.taskContext(taskID: context.task.id) else {
            dismiss()
            return
        }

        let initialStatus = live.task.status
        let initialArchived = live.task.isArchived
        let destinationJobID = selectedJobID
        let destinationProjectID = selectedJobID == nil ? nil : selectedProjectID
        let destinationOperationID = selectedJobID == nil ? nil : selectedOperationID

        let cal = Calendar.current
        let ok = store.updateTask(
            context: live,
            destinationJobID: destinationJobID,
            destinationProjectID: destinationProjectID,
            destinationOperationID: destinationOperationID
        ) { task in
            task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.summary = ""
            task.why = ""
            task.nextStep = ""
            task.waitingOn = nil
            task.toolBundleIDs = Task.normalizedToolBundleIDs(toolBundleIDs)
            task.energy = energy
            task.cadence = cadence
            task.priority = 3
            task.startDate = hasStartDate ? cal.startOfDay(for: planStart) : nil
            task.endDate = hasEndDate ? cal.startOfDay(for: planEnd) : nil
            task.blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(blockedByTaskIDs, for: task.id)
            if cadence == .oneOff {
                task.repeatEveryMinutes = nil
                task.kpiTarget = nil
                task.kpiUnit = nil
                task.kpiRoundsRemaining = nil
                task.kpiCount = 0
            } else if cadence == .repeatable {
                task.repeatEveryMinutes = repeatEveryMinutes
                task.kpiTarget = nil
                task.kpiUnit = nil
                task.kpiRoundsRemaining = nil
                task.kpiCount = 0
            } else {
                task.repeatEveryMinutes = hasRepeatDelay ? repeatEveryMinutes : nil
                task.kpiTarget = kpiTarget
                task.kpiUnit = nil
                task.kpiRoundsRemaining = hasKpiRounds ? kpiRoundsRemaining : nil
                task.kpiCount = max(0, min(kpiCount, kpiTarget))
                task.progress = min(Double(task.kpiCount) / Double(max(kpiTarget, 1)), 1)
            }
        }

        guard ok else { return }

        if let refreshed = store.taskContext(taskID: context.task.id), initialArchived != isArchived {
            store.setTaskArchived(refreshed, archived: isArchived)
        }

        if let refreshed = store.taskContext(taskID: context.task.id) {
            let wantNow = isScheduledNow && !isArchived
            if refreshed.task.isScheduledNow != wantNow {
                store.toggleTaskNow(refreshed)
            }

            if initialStatus != status,
               let latest = store.taskContext(taskID: context.task.id) {
                store.setTaskStatus(latest, status: status)
            } else if let latest = store.taskContext(taskID: context.task.id),
                      store.isTaskBlocked(latest),
                      latest.task.status == .active {
                store.setTaskStatus(latest, status: .queued, bypassMultitaskUpgradePrompt: true)
            }
        }

        dismiss()
    }

    private var dependencyCandidates: [TaskContext] {
        store.taskContexts
            .filter { candidate in
                candidate.task.id != context.task.id
                    && !candidate.task.isArchived
                    && !blockedByTaskIDs.contains(candidate.task.id)
                    && !wouldCreateCycle(ifAdding: candidate.task.id)
            }
            .sorted { $0.task.title.localizedCaseInsensitiveCompare($1.task.title) == .orderedAscending }
    }

    private func wouldCreateCycle(ifAdding prerequisiteID: UUID) -> Bool {
        guard let prerequisite = store.taskContext(taskID: prerequisiteID) else { return true }
        var visited = Set<UUID>()
        var stack = prerequisite.task.blockedByTaskIDs
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            if current == context.task.id { return true }
            guard let ctx = store.taskContext(taskID: current) else { continue }
            stack.append(contentsOf: ctx.task.blockedByTaskIDs)
        }
        return false
    }

    private func blockerTitle(for id: UUID) -> String {
        store.taskContext(taskID: id)?.task.title ?? "Missing task"
    }

    private func blockerMeta(for id: UUID) -> String {
        guard let ctx = store.taskContext(taskID: id) else { return "Task was deleted" }
        let status = ctx.task.status == .done ? "Done" : ctx.task.status.title
        let location = ctx.metaSubtitleParts.joined(separator: " · ")
        return location.isEmpty ? status : "\(status) · \(location)"
    }

    private var availableProjects: [ProjectContext] {
        guard let selectedJobID else { return [] }
        return store.projectContexts(jobID: selectedJobID)
    }

    private var availableOperations: [OperationContext] {
        guard let selectedJobID else { return [] }
        return store.operationContexts(jobID: selectedJobID).filter { !$0.operation.isArchived }
    }

    private var locationSummary: String {
        if let selectedJobID,
           let job = store.jobs.first(where: { $0.id == selectedJobID }) {
            if let selectedProjectID,
               let project = availableProjects.first(where: { $0.project.id == selectedProjectID }) {
                return "\(job.title) / \(project.project.displayTitle)"
            }
            if let selectedOperationID,
               let operation = availableOperations.first(where: { $0.operation.id == selectedOperationID }) {
                return "\(job.title) / \(operation.operation.title)"
            }
            return "\(job.title) / Field"
        }

        return "Inbox"
    }

    private func syncProjectSelection() {
        guard let selectedJobID else {
            selectedProjectID = nil
            selectedOperationID = nil
            return
        }

        if let selectedProjectID,
           !availableProjects.contains(where: { $0.project.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
        if let selectedOperationID,
           !availableOperations.contains(where: { $0.operation.id == selectedOperationID }) {
            self.selectedOperationID = nil
        }

        if !store.jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = nil
            self.selectedProjectID = nil
            self.selectedOperationID = nil
        }
    }
}
