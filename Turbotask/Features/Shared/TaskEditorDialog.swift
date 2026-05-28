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
    @State private var toolsPickerOpen = false
    @State private var hasStartDate: Bool
    @State private var hasEndDate: Bool
    @State private var planStart = Date()
    @State private var planEnd = Date()

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
        _hasStartDate = State(initialValue: context.task.startDate != nil)
        _hasEndDate = State(initialValue: context.task.endDate != nil)
        _planStart = State(initialValue: context.task.startDate ?? Date())
        _planEnd = State(initialValue: context.task.endDate ?? Date())
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
                        Picker("Job", selection: $selectedJobID) {
                            Text("Inbox (no job)").tag(nil as UUID?)
                            ForEach(store.jobs) { job in
                                Text(job.title).tag(Optional(job.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if selectedJobID != nil {
                            Picker("Project", selection: $selectedProjectID) {
                                Text("None — task on job only").tag(nil as UUID?)
                                ForEach(availableProjects) { project in
                                    Text(project.project.displayTitle).tag(Optional(project.project.id))
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

                    Toggle("Archived (hidden from Now and job lists)", isOn: $isArchived)
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

        let cal = Calendar.current
        let ok = store.updateTask(
            context: live,
            destinationJobID: destinationJobID,
            destinationProjectID: destinationProjectID
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
            }
        }

        dismiss()
    }

    private var availableProjects: [ProjectContext] {
        guard let selectedJobID else { return [] }
        return store.projectContexts(jobID: selectedJobID)
    }

    private var locationSummary: String {
        if let selectedJobID,
           let job = store.jobs.first(where: { $0.id == selectedJobID }) {
            if let selectedProjectID,
               let project = availableProjects.first(where: { $0.project.id == selectedProjectID }) {
                return "\(job.title) / \(project.project.displayTitle)"
            }
            return "\(job.title) / No project"
        }

        return "Inbox"
    }

    private func syncProjectSelection() {
        guard let selectedJobID else {
            selectedProjectID = nil
            return
        }

        if let selectedProjectID,
           !availableProjects.contains(where: { $0.project.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }

        if !store.jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = nil
            self.selectedProjectID = nil
        }
    }
}
