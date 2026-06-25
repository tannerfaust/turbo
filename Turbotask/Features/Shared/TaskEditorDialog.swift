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
    @State private var notes: String
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
    @State private var subtasks: [TaskSubtask]
    @State private var aiProvider: AIDependencyProvider?

    init(context: TaskContext) {
        self.context = context
        _title = State(initialValue: context.task.title)
        _notes = State(initialValue: context.task.summary)
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
        _subtasks = State(initialValue: context.task.subtasks)
        _aiProvider = State(initialValue: context.task.aiProvider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            Divider().opacity(0.65)
            editorContent
            Divider().opacity(0.65)
            editorFooter
        }
        .frame(width: 760)
        .background(TurboTheme.backgroundRaised)
        .overlay { keyboardTraps }
        .sheet(isPresented: $toolsPickerOpen) {
            TaskToolsPickerSheet(bundleIDs: $toolBundleIDs)
                .environmentObject(store)
        }
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
        .animation(.easeInOut(duration: 0.18), value: cadence)
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            fieldPill
            if selectedJobID != nil {
                projectPill
            }
            Spacer(minLength: 8)
            ComposerNowButton(isOn: $isScheduledNow, glowColor: destinationAccent)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(TurboTheme.nestedCardFill))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close · Esc")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ComposerStatusMenuButton(selection: $status, accentColor: destinationAccent)
                TextField("Task title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
            }

            TextField("Add description or notes...", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(TurboTheme.ink)
                .lineLimit(3...)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 120, alignment: .topLeading)

            FlowLayout(spacing: 6) {
                energyPill
                aiProviderPill
                cadencePill
                toolsPill
                subtasksPill
                planPill
            }
            .padding(.top, 12)

            patternSettings
            dependenciesSection
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var editorFooter: some View {
        HStack(spacing: 12) {
            Button { toolsPickerOpen = true } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Toggle("Archived", isOn: $isArchived)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk)

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save changes") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var destinationAccent: Color {
        guard let selectedJobID,
              let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
            return TurboTheme.inboxAccent
        }
        return job.palette.color
    }

    private var energyPill: some View {
        ComposerCapturePill(
            icon: "bolt.fill",
            iconColor: destinationAccent,
            title: energy.shortTitle,
            isActive: energy != .deepFocus,
            helpText: "Work mode: \(energy.title)"
        ) {
            ForEach(TaskEnergy.allCases) { option in
                Button {
                    energy = option
                } label: {
                    HStack {
                        Text(option.title)
                        if energy == option { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var aiProviderPill: some View {
        ComposerCapturePill(
            icon: aiProvider?.symbol ?? "cpu",
            iconColor: aiProvider?.accent ?? TurboTheme.mutedInk,
            title: aiProvider?.shortTitle ?? "AI",
            isActive: aiProvider != nil,
            helpText: "AI dependency: Claude, Codex, Cursor, or Antigravity"
        ) {
            Button {
                aiProvider = nil
            } label: {
                HStack {
                    Text("None")
                    if aiProvider == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(AIDependencyProvider.allCases) { provider in
                Button {
                    aiProvider = provider
                } label: {
                    HStack {
                        Label(provider.title, systemImage: provider.symbol)
                        if aiProvider == provider { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var fieldPill: some View {
        ComposerCapturePill(
            icon: selectedJobID == nil ? "tray" : "briefcase",
            title: fieldLabel,
            isActive: selectedJobID != nil,
            helpText: "Field: \(fieldLabel)"
        ) {
            Button {
                selectedJobID = nil
                selectedProjectID = nil
                selectedOperationID = nil
            } label: {
                HStack {
                    Text("Inbox")
                    if selectedJobID == nil { Image(systemName: "checkmark") }
                }
            }
            if !store.jobs.isEmpty {
                Divider()
                ForEach(store.jobs) { job in
                    Button {
                        selectedJobID = job.id
                        selectedProjectID = nil
                        selectedOperationID = nil
                    } label: {
                        HStack {
                            Text(job.title)
                            if selectedJobID == job.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }

    private var projectPill: some View {
        ComposerCapturePill(
            icon: selectedOperationID == nil ? "square.stack.3d.up" : "arrow.triangle.2.circlepath",
            title: placementLabel,
            isActive: selectedProjectID != nil || selectedOperationID != nil,
            helpText: "Placement: \(placementLabel)"
        ) {
            Button {
                selectedProjectID = nil
                selectedOperationID = nil
            } label: {
                HStack {
                    Text("Field only")
                    if selectedProjectID == nil && selectedOperationID == nil { Image(systemName: "checkmark") }
                }
            }
            if !availableProjects.isEmpty {
                Divider()
                Text("Projects")
                ForEach(availableProjects) { item in
                    Button {
                        selectedProjectID = item.project.id
                        selectedOperationID = nil
                    } label: {
                        HStack {
                            Text(item.project.displayTitle)
                            if selectedProjectID == item.project.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            if !availableOperations.isEmpty {
                Divider()
                Text("Operations")
                ForEach(availableOperations) { item in
                    Button {
                        selectedOperationID = item.operation.id
                        selectedProjectID = nil
                    } label: {
                        HStack {
                            Text(item.operation.title)
                            if selectedOperationID == item.operation.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }

    private var cadencePill: some View {
        ComposerCapturePill(
            icon: cadenceIcon,
            title: cadence.title,
            isActive: cadence != .oneOff,
            helpText: "Pattern: \(cadence.title)"
        ) {
            ForEach(TaskCadence.allCases) { option in
                Button {
                    cadence = option
                } label: {
                    HStack {
                        Text(option.title)
                        if cadence == option { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var toolsPill: some View {
        ComposerCapturePill(
            icon: "wrench.and.screwdriver",
            title: toolBundleIDs.isEmpty ? "Tools" : "\(toolBundleIDs.count) tool\(toolBundleIDs.count == 1 ? "" : "s")",
            isActive: !toolBundleIDs.isEmpty,
            helpText: "Choose apps needed for this task"
        ) {
            Button("Choose apps…") { toolsPickerOpen = true }
            if !toolBundleIDs.isEmpty {
                Button("Clear tools", role: .destructive) { toolBundleIDs = [] }
            }
        }
    }

    private var subtasksPill: some View {
        TaskSubtasksPill(subtasks: $subtasks, accentColor: destinationAccent)
    }

    private var planPill: some View {
        ComposerCapturePill(
            icon: "calendar",
            title: planLabel,
            isActive: hasStartDate || hasEndDate,
            helpText: "Set optional plan dates"
        ) {
            Toggle("Start date", isOn: $hasStartDate)
            if hasStartDate {
                DatePicker("Starts", selection: $planStart, displayedComponents: .date)
            }
            Toggle("Target end", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Ends", selection: $planEnd, displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private var patternSettings: some View {
        if cadence != .oneOff {
            HStack(spacing: 14) {
                if cadence == .repeatable {
                    Text("Reappear after completion")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(durationLabel(repeatEveryMinutes))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    Stepper("", value: $repeatEveryMinutes, in: 15...2880, step: 15)
                        .labelsHidden()
                        .controlSize(.small)
                } else {
                    compactStepper("Target", value: $kpiTarget, range: 1...500)
                    compactStepper("Current", value: $kpiCount, range: 0...10_000)
                    Toggle("Rounds", isOn: $hasKpiRounds)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    if hasKpiRounds {
                        compactStepper("Left", value: $kpiRoundsRemaining, range: 1...50)
                    }
                    Toggle("Delay", isOn: $hasRepeatDelay)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(TurboTheme.mutedInk)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(TurboTheme.nestedCardFill.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
            )
            .padding(.top, 12)
        }
    }

    private func compactStepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(label) \(value.wrappedValue)")
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                Text("Starts after")
                    .font(.system(size: 13, weight: .semibold))
                if !blockedByTaskIDs.isEmpty {
                    Text("\(blockedByTaskIDs.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                Spacer()
                dependencyMenu
            }

            if blockedByTaskIDs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text("No prerequisites — this task can start anytime")
                }
                .font(.system(size: 12))
                .foregroundStyle(TurboTheme.mutedInk)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TurboTheme.nestedCardFill.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(blockedByTaskIDs.enumerated()), id: \.element) { index, blockerID in
                            dependencyRow(blockerID)
                            if index < blockedByTaskIDs.count - 1 {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                }
                .frame(maxHeight: 126)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TurboTheme.nestedCardFill.opacity(0.45))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
                )
            }
        }
        .padding(.top, 14)
    }

    private var dependencyMenu: some View {
        Menu {
            if dependencyCandidates.isEmpty {
                Text("No tasks available")
            } else {
                ForEach(dependencyCandidates) { candidate in
                    Button {
                        blockedByTaskIDs.append(candidate.task.id)
                        blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(blockedByTaskIDs, for: context.task.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(candidate.task.title)
                            if !candidate.metaSubtitleParts.isEmpty {
                                Text(candidate.metaSubtitleParts.joined(separator: " · "))
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Add prerequisite", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(dependencyCandidates.isEmpty)
    }

    private func dependencyRow(_ blockerID: UUID) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.taskContext(taskID: blockerID)?.task.status.accent ?? TurboTheme.mutedInk)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(blockerTitle(for: blockerID))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
                Text(blockerMeta(for: blockerID))
                    .font(.system(size: 11))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                blockedByTaskIDs.removeAll { $0 == blockerID }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Remove prerequisite")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var keyboardTraps: some View {
        VStack(spacing: 0) {
            Button(action: { status = .queued }) { EmptyView() }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button(action: { status = .active }) { EmptyView() }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button(action: { status = .waiting }) { EmptyView() }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button(action: { status = .paused }) { EmptyView() }
                .keyboardShortcut("4", modifiers: [.command, .option])
            Button(action: { status = .done }) { EmptyView() }
                .keyboardShortcut("5", modifiers: [.command, .option])
            Button(action: { isScheduledNow.toggle() }) { EmptyView() }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fieldLabel: String {
        guard let selectedJobID,
              let job = store.jobs.first(where: { $0.id == selectedJobID }) else { return "Inbox" }
        return job.title
    }

    private var placementLabel: String {
        if let selectedProjectID,
           let item = availableProjects.first(where: { $0.project.id == selectedProjectID }) {
            return item.project.displayTitle
        }
        if let selectedOperationID,
           let item = availableOperations.first(where: { $0.operation.id == selectedOperationID }) {
            return item.operation.title
        }
        return "Project / Operation"
    }

    private var cadenceIcon: String {
        switch cadence {
        case .oneOff: "1.circle"
        case .repeatable: "repeat"
        case .kpi: "number"
        }
    }

    private var planLabel: String {
        if hasStartDate && hasEndDate { return "Plan dates" }
        if hasStartDate { return "Start date" }
        if hasEndDate { return "End date" }
        return "Plan"
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60) hr" }
        return "\(minutes / 60) hr \(minutes % 60) min"
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
            task.summary = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.toolBundleIDs = Task.normalizedToolBundleIDs(toolBundleIDs)
            task.aiProvider = aiProvider
            task.energy = energy
            task.cadence = cadence
            task.priority = 3
            task.startDate = hasStartDate ? cal.startOfDay(for: planStart) : nil
            task.endDate = hasEndDate ? cal.startOfDay(for: planEnd) : nil
            task.blockedByTaskIDs = Task.normalizedBlockedByTaskIDs(blockedByTaskIDs, for: task.id)
            task.subtasks = Task.normalizedSubtasks(subtasks)
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
