//
//  ItemComposerSheet.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct ItemComposerSheet: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TurboTaskStore.ComposerContext

    @State private var jobTitle = ""
    @State private var jobSummary = ""
    @State private var selectedPalette: JobPalette = .forest

    @State private var selectedJobID: UUID?
    @State private var projectTitle = ""
    @State private var projectOutcome = ""
    @State private var projectEmoji = ""

    @State private var selectedProjectID: UUID?
    @State private var taskTitle = ""
    @State private var taskStatus: TaskStatus = .queued
    @State private var taskEnergy: TaskEnergy = .deepFocus
    @State private var taskCadence: TaskCadence = .oneOff
    @State private var taskIsScheduledNow = false
    @State private var taskRepeatEveryMinutes = 60
    @State private var taskKpiTarget = 10
    @State private var taskKpiUnit = ""
    @State private var taskToolBundleIDs: [String] = []
    @State private var taskToolsPickerOpen = false
    @State private var taskHasStartDate = false
    @State private var taskHasEndDate = false
    @State private var taskStartDate = Date()
    @State private var taskEndDate = Date()

    init(context: TurboTaskStore.ComposerContext) {
        self.context = context
        _selectedJobID = State(initialValue: context.preferredJobID)
        _selectedProjectID = State(initialValue: context.preferredProjectID)
        _taskIsScheduledNow = State(initialValue: context.scheduleForNow)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }

            taskComposerKeyTraps
                .allowsHitTesting(false)
        }
        .frame(width: 560, height: 560)
        .background(TurboTheme.backgroundRaised)
        .onAppear {
            syncProjectSelection()
        }
        .onChange(of: selectedJobID) {
            syncProjectSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .padding(22)
    }

    @ViewBuilder
    private var content: some View {
        switch context.kind {
        case .job:
            jobForm
        case .project:
            projectForm
        case .task:
            taskForm
        }
    }

    /// Local shortcuts while the task composer is open (⌥⌘1…5 status · ⌥⌘B toggle Now).
    @ViewBuilder
    private var taskComposerKeyTraps: some View {
        if context.kind == .task {
            VStack(spacing: 0) {
                Button("") { taskStatus = .queued }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("") { taskStatus = .active }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("") { taskStatus = .waiting }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("") { taskStatus = .paused }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("") { taskStatus = .done }
                    .keyboardShortcut("5", modifiers: [.command, .option])
                Button("") { taskIsScheduledNow.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                store.clearComposer()
            }
            .keyboardShortcut(.cancelAction)
            .trainingWheelsTooltip("Dismiss · Esc")

            Spacer()

            Button(primaryButtonTitle) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
            .trainingWheelsTooltip("Save · Return")
        }
        .padding(22)
    }

    private var jobForm: some View {
        Form {
            TextField("Job title", text: $jobTitle)
            TextField("What this job is for", text: $jobSummary, axis: .vertical)
                .lineLimit(3...5)
            LabeledContent("Accent") {
                JobPaletteSwatchRow(selection: $selectedPalette)
            }
        }
        .formStyle(.grouped)
    }

    private var projectForm: some View {
        Group {
            if store.jobs.isEmpty {
                prerequisiteMessage(
                    title: "Create a job first",
                    detail: "Projects need a parent job before they can exist."
                )
            } else {
                Form {
                    Picker("Job", selection: $selectedJobID) {
                        Text("Choose job…").tag(nil as UUID?)
                        ForEach(store.jobs) { job in
                            Text(job.title).tag(Optional(job.id))
                        }
                    }
                    LabeledContent("Icon") {
                        EmojiPickButton(emoji: $projectEmoji)
                    }
                    TextField("Project title", text: $projectTitle)
                    TextField("What outcome this project should create", text: $projectOutcome, axis: .vertical)
                        .lineLimit(3...5)
                }
                .formStyle(.grouped)
            }
        }
    }

    private var taskForm: some View {
        Form {
            if store.jobs.isEmpty {
                Text("New tasks go to Inbox. Add a job anytime if you want to group work.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
            } else {
                Picker("Job", selection: $selectedJobID) {
                    Text("Inbox (no job)").tag(nil as UUID?)
                    ForEach(store.jobs) { job in
                        Text(job.title).tag(Optional(job.id))
                    }
                }

                if selectedJobID != nil {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("None — task on job only").tag(nil as UUID?)
                        ForEach(availableProjects) { context in
                            Text(context.project.displayTitle).tag(Optional(context.project.id))
                        }
                    }
                }
            }

            TextField("Task title", text: $taskTitle)

            Picker("Status", selection: $taskStatus) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }

            Picker("Work mode", selection: $taskEnergy) {
                ForEach(TaskEnergy.allCases) { energy in
                    Text(energy.title).tag(energy)
                }
            }

            Picker("Task pattern", selection: $taskCadence) {
                ForEach(TaskCadence.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }

            Toggle("Put on Now", isOn: $taskIsScheduledNow)

            Section("Plan (informative)") {
                Toggle("Start date", isOn: $taskHasStartDate)
                if taskHasStartDate {
                    DatePicker("Starts", selection: $taskStartDate, displayedComponents: .date)
                }
                Toggle("Target end date", isOn: $taskHasEndDate)
                if taskHasEndDate {
                    DatePicker("Ends", selection: $taskEndDate, displayedComponents: .date)
                }
            }

            if taskCadence != .oneOff {
                Stepper(
                    "Reappear after: \(taskRepeatEveryMinutes) min",
                    value: $taskRepeatEveryMinutes,
                    in: 15...2880,
                    step: 15
                )
            }

            if taskCadence == .kpi {
                Stepper("KPI target: \(taskKpiTarget)", value: $taskKpiTarget, in: 1...500, step: 1)
                TextField("KPI unit", text: $taskKpiUnit)
            }

            LabeledContent("Tools needed") {
                HStack(spacing: 10) {
                    TaskToolsIconRow(bundleIDs: taskToolBundleIDs, iconSize: 22, maxIcons: 6)
                    Spacer(minLength: 0)
                    Button("Choose apps…") {
                        taskToolsPickerOpen = true
                    }
                    .buttonStyle(.bordered)
                    .trainingWheelsTooltip("Pick Mac apps · in the sheet, focus search and use ↑ ↓ + Return")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $taskToolsPickerOpen) {
            TaskToolsPickerSheet(bundleIDs: $taskToolBundleIDs)
                .environmentObject(store)
        }
    }

    private func prerequisiteMessage(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
            Text(detail)
                .font(.body)
                .foregroundStyle(TurboTheme.mutedInk)

            Button("Create Job") {
                store.clearComposer()
                store.openComposer(.job)
            }
            .buttonStyle(.borderedProminent)
            .trainingWheelsTooltip("Start with a job, then add projects and tasks")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }

    private var title: String {
        switch context.kind {
        case .job:
            "New Job"
        case .project:
            "New Project"
        case .task:
            "New Task"
        }
    }

    private var subtitle: String {
        switch context.kind {
        case .job:
            "Jobs are major work domains such as a company, client, or personal area."
        case .project:
            "Projects are finite initiatives nested inside a job."
        case .task:
            "Tasks can live in Inbox, on a job without a project, or inside a project. All can appear on Now."
        }
    }

    private var primaryButtonTitle: String {
        switch context.kind {
        case .job:
            "Create Job"
        case .project:
            "Create Project"
        case .task:
            "Create Task"
        }
    }

    private var canSave: Bool {
        switch context.kind {
        case .job:
            !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .project:
            selectedJobID != nil && !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .task:
            !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (taskCadence != .kpi || !taskKpiUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var availableProjects: [ProjectContext] {
        guard let selectedJobID else { return [] }
        return store.projectContexts.filter { $0.jobID == selectedJobID }
    }

    private func syncProjectSelection() {
        guard context.kind == .task else { return }

        if selectedJobID == nil {
            selectedProjectID = nil
            return
        }

        if let pid = selectedProjectID,
           !availableProjects.contains(where: { $0.project.id == pid }) {
            selectedProjectID = nil
        }
    }

    private func save() {
        switch context.kind {
        case .job:
            store.addJob(
                title: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: jobSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                palette: selectedPalette
            )
        case .project:
            guard let selectedJobID else { return }
            store.addProject(
                title: projectTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                outcome: projectOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
                iconEmoji: projectEmoji,
                jobID: selectedJobID
            )
        case .task:
            let cal = Calendar.current
            let start = taskHasStartDate ? cal.startOfDay(for: taskStartDate) : nil
            let end = taskHasEndDate ? cal.startOfDay(for: taskEndDate) : nil
            store.addTask(
                title: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                status: taskStatus,
                energy: taskEnergy,
                cadence: taskCadence,
                isScheduledNow: taskIsScheduledNow,
                repeatEveryMinutes: taskCadence == .oneOff ? nil : taskRepeatEveryMinutes,
                kpiTarget: taskCadence == .kpi ? taskKpiTarget : nil,
                kpiUnit: taskCadence == .kpi ? taskKpiUnit : nil,
                toolBundleIDs: taskToolBundleIDs,
                jobID: selectedJobID,
                projectID: selectedProjectID,
                startDate: start,
                endDate: end
            )
        }

        store.clearComposer()
    }
}
