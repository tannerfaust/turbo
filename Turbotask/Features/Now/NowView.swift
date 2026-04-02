//
//  NowView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let nowDragUTTypes: [UTType] = [.plainText, .text]

/// Mutable flags read from the key-event monitor (must be a reference type).
private final class NowKeyboardGate {
    var taskEditorOpen = false
    var quickCreateExpanded = false
    /// When quick add is open, ⌘T calls this instead of opening the task composer.
    var toggleQuickCreateScheduleForNow: (() -> Void)?
}

struct NowView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var viewMode: NowBoardMode = .list
    @State private var editingTask: TaskContext?
    @State private var quickCreateExpanded = false
    /// Used when creating from the inline quick-add bar (⌘T while bar is open toggles this).
    @State private var quickCreateScheduleForNow = true
    @State private var keyboardGate = NowKeyboardGate()
    @State private var localKeyMonitor: Any?

    private var weekdayTitle: String {
        Date.now.formatted(.dateTime.weekday(.wide))
    }

    private var dateTitle: String {
        Date.now.formatted(.dateTime.day().month(.abbreviated))
    }

    private var upcomingRepeatables: [TaskContext] {
        store.taskContexts
            .filter { context in
                context.task.isScheduledNow
                    && context.task.cadence != .oneOff
                    && !context.task.isAvailableNow
                    && context.task.nextAvailableAt != nil
            }
            .sorted {
                ($0.task.nextAvailableAt ?? .distantFuture) < ($1.task.nextAvailableAt ?? .distantFuture)
            }
    }

    private var availableJobChoices: [Job] {
        let visibleJobIDs = Set(store.visibleNowJobIDs)
        return store.jobs.filter { job in
            !visibleJobIDs.contains(job.id)
        }
    }

    private var availableProjectChoices: [ProjectContext] {
        let visibleProjectIDs = Set(store.visibleNowProjectIDs)
        let allowedJobIDs = Set(store.visibleNowJobIDs)
        return store.projectContexts.filter { context in
            guard allowedJobIDs.contains(context.jobID) else { return false }
            return !visibleProjectIDs.contains(context.project.id)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TurboPageHeader(
                    title: "Now",
                    trailing: AnyView(
                        Picker("View", selection: $viewMode) {
                            ForEach(NowBoardMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbol)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 192)
                        .trainingWheelsTooltip("List vs tree · ⇧⌘L")
                    )
                )

                TodayScopeBar(
                    weekdayTitle: weekdayTitle,
                    dateTitle: dateTitle,
                    visibleJobs: store.visibleNowJobs,
                    visibleProjects: store.visibleNowProjects,
                    availableJobChoices: availableJobChoices,
                    availableProjectChoices: availableProjectChoices
                )
                .environmentObject(store)

                if !upcomingRepeatables.isEmpty {
                    ReturningLaterCard(tasks: upcomingRepeatables)
                }

                NowQuickCreateBar(isExpanded: $quickCreateExpanded, scheduleForNow: $quickCreateScheduleForNow)
                    .environmentObject(store)
                    .padding(.bottom, 6)

                TrainingWheelsHint(text: "⌘N or ⇧⌘A toggles quick add · Esc closes · With the bar open, ⌘T toggles Schedule for Now.")
                    .padding(.bottom, 2)

                switch viewMode {
                case .list:
                    ListBoard(
                        tasks: store.scopedNowTasks,
                        onEditTask: { editingTask = $0 }
                    )
                    .environmentObject(store)
                case .tree:
                    NowTreeWithDoneSection(
                        openTasks: store.scopedNowTasks.filter { $0.task.status != .done },
                        doneTasks: store.scopedNowTasks.filter { $0.task.status == .done },
                        treeGroups: store.nowTreeGroups,
                        onEditTask: { editingTask = $0 }
                    )
                    .environmentObject(store)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            keyboardGate.taskEditorOpen = editingTask != nil
            keyboardGate.quickCreateExpanded = quickCreateExpanded
            keyboardGate.toggleQuickCreateScheduleForNow = { quickCreateScheduleForNow.toggle() }
            store.ensureSelection()
            installNowLocalKeyMonitor()
        }
        .onDisappear {
            removeNowLocalKeyMonitor()
        }
        .onChange(of: editingTask) { _, newValue in
            keyboardGate.taskEditorOpen = newValue != nil
        }
        .onChange(of: quickCreateExpanded) { _, expanded in
            keyboardGate.quickCreateExpanded = expanded
        }
        .onChange(of: store.nowShortcutAction, initial: true) { _, action in
            guard let action else { return }
            defer { store.clearNowShortcutAction() }
            switch action {
            case .focusQuickAdd:
                quickCreateExpanded.toggle()
            case .toggleViewMode:
                viewMode = viewMode == .list ? .tree : .list
            case .openEditorForSelection:
                openEditorForSelection()
            case .startSelectedTask:
                applyToSelectedTask { store.setTaskStatus($0, status: .active) }
            case .pauseSelectedTask:
                applyToSelectedTask { store.setTaskStatus($0, status: .paused) }
            case .markSelectedDone:
                applyToSelectedTask { store.setTaskStatus($0, status: .done) }
            case .markSelectedWaiting:
                applyToSelectedTask { store.setTaskStatus($0, status: .waiting) }
            }
        }
        .onKeyPress(.escape) {
            if quickCreateExpanded {
                quickCreateExpanded = false
                return .handled
            }
            return .ignored
        }
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
                .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
    }

    private var selectedTaskContext: TaskContext? {
        guard case let .task(jobID, projectID, taskID) = store.selection else { return nil }
        return store.taskContext(jobID: jobID, projectID: projectID, taskID: taskID)
    }

    private func openEditorForSelection() {
        guard let context = selectedTaskContext else { return }
        editingTask = context
    }

    private func applyToSelectedTask(_ action: (TaskContext) -> Void) {
        guard let context = selectedTaskContext else { return }
        action(context)
    }

    private func installNowLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        let gate = keyboardGate
        let st = store
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let commandDown = event.modifierFlags.contains(.command)
            let consume = MainActor.assumeIsolated {
                NowLocalKeyRouter.shouldConsumeKey(
                    keyCode: keyCode,
                    commandDown: commandDown,
                    store: st,
                    gate: gate
                )
            }
            return consume ? nil : event
        }
    }

    private func removeNowLocalKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        localKeyMonitor = nil
    }
}

// MARK: - Local keys (arrows + return) on main thread

private enum NowLocalKeyRouter {
    /// `true` if the key event should be consumed (not passed through).
    @MainActor
    static func shouldConsumeKey(
        keyCode: UInt16,
        commandDown: Bool,
        store: TurboTaskStore,
        gate: NowKeyboardGate
    ) -> Bool {
        guard store.selectedScreen == .now else { return false }
        guard !gate.taskEditorOpen else { return false }
        guard store.composer == nil else { return false }

        // ⌘T while quick add is open: toggle "schedule for Now" (not the full task composer).
        if gate.quickCreateExpanded, commandDown, keyCode == 17 {
            gate.toggleQuickCreateScheduleForNow?()
            return true
        }

        guard !gate.quickCreateExpanded else { return false }
        guard !textInputHasFocus() else { return false }

        // ↑ / ↓ / ← / → — same order as the Now list (scoped tasks).
        switch keyCode {
        case 126, 123:
            store.moveNowSelection(-1)
            return true
        case 125, 124:
            store.moveNowSelection(1)
            return true
        case 36:
            if !commandDown, let ctx = selectedNowTask(in: store) {
                store.setTaskStatus(ctx, status: .active)
                return true
            }
            return false
        default:
            return false
        }
    }

    private static func selectedNowTask(in store: TurboTaskStore) -> TaskContext? {
        guard case let .task(j, p, tid) = store.selection else { return nil }
        return store.taskContext(jobID: j, projectID: p, taskID: tid)
    }

    private static func textInputHasFocus() -> Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        if r is NSTextView { return true }
        if r is NSTextField { return true }
        let desc = String(describing: type(of: r))
        if desc.contains("FieldEditor") { return true }
        if desc.contains("NSTextView") { return true }
        return false
    }
}

private enum NowQuickCreateTarget: Hashable {
    case inbox
    case jobTask(jobID: UUID)
    case project(jobID: UUID, projectID: UUID)
}

private struct NowQuickCreateBar: View {
    @EnvironmentObject private var store: TurboTaskStore

    @Binding var isExpanded: Bool
    @Binding var scheduleForNow: Bool

    @FocusState private var isTitleFocused: Bool
    @State private var title = ""
    @State private var selectedEnergy: TaskEnergy = .deepFocus
    @State private var target: NowQuickCreateTarget = .inbox

    private var projectMenuSources: [ProjectContext] {
        if !store.visibleNowProjects.isEmpty {
            return store.visibleNowProjects
        }
        return store.projectContexts
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            plusButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Create task…", text: $title)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($isTitleFocused)
                            .onSubmit(createTask)

                        Spacer(minLength: 0)

                        Toggle("Now", isOn: $scheduleForNow)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                            .trainingWheelsTooltip("Add to Now when created · ⌘T while this bar is open")

                        projectMenu

                        Button(action: createTask) {
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canCreate ? TurboTheme.ink : TurboTheme.mutedInk.opacity(0.5))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(TurboTheme.nestedCardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(TurboTheme.divider, lineWidth: 1)
                                )
                        )
                        .disabled(!canCreate)
                        .trainingWheelsTooltip("Create task · Return")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TurboTheme.cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(TurboTheme.cardStroke, lineWidth: 1)
                            )
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(TaskEnergy.allCases) { energy in
                                typeChip(for: energy)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            syncQuickCreateTarget()
        }
        .onChange(of: store.visibleNowProjects.map(\.project.id)) {
            syncQuickCreateTarget()
        }
        .onChange(of: store.projectContexts.map(\.project.id)) {
            syncQuickCreateTarget()
        }
        .onChange(of: store.jobs.map(\.id)) {
            syncQuickCreateTarget()
        }
        .onChange(of: isExpanded) {
            if isExpanded {
                syncQuickCreateTarget()
                isTitleFocused = true
            } else {
                title = ""
                isTitleFocused = false
            }
        }
    }

    private var plusButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(TurboTheme.divider, lineWidth: 1)
                    )
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
                Text(isExpanded ? "Cancel" : "New task")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .buttonStyle(.plain)
        .trainingWheelsTooltip(isExpanded ? "Close quick add · ⌘N · ⇧⌘A · Esc" : "Open quick add · ⌘N · ⇧⌘A")
    }

    private var projectMenu: some View {
        Menu {
            Button {
                target = .inbox
            } label: {
                Label("Inbox", systemImage: target == .inbox ? "checkmark" : "tray")
            }

            if !store.jobs.isEmpty {
                Menu("Job tasks") {
                    ForEach(store.jobs) { job in
                        Button {
                            target = .jobTask(jobID: job.id)
                        } label: {
                            Label(job.title, systemImage: jobTaskMenuIcon(jobID: job.id))
                        }
                    }
                }
            }

            if !projectMenuSources.isEmpty {
                Menu("Projects") {
                    ForEach(projectMenuSources) { context in
                        Button {
                            target = .project(jobID: context.jobID, projectID: context.project.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: projectMenuIcon(context: context))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(context.jobColor)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(context.project.displayTitle)
                                    Text(context.jobTitle)
                                        .font(.caption2)
                                        .foregroundStyle(TurboTheme.mutedInk)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(targetMenuTint)
                    .frame(width: 7, height: 7)

                Text(targetMenuTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TurboTheme.nestedCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(TurboTheme.divider, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private func jobTaskMenuIcon(jobID: UUID) -> String {
        if case .jobTask(let jid) = target, jid == jobID { return "checkmark.circle.fill" }
        return "briefcase"
    }

    private func projectMenuIcon(context: ProjectContext) -> String {
        if case .project(let jid, let pid) = target,
           jid == context.jobID, pid == context.project.id {
            return "checkmark.circle.fill"
        }
        return "circle.fill"
    }

    private var targetMenuTint: Color {
        switch target {
        case .inbox:
            TurboTheme.slate
        case .jobTask(let jobID):
            store.jobs.first(where: { $0.id == jobID })?.palette.color ?? TurboTheme.slate
        case .project(let jobID, _):
            store.jobs.first(where: { $0.id == jobID })?.palette.color ?? TurboTheme.slate
        }
    }

    private var targetMenuTitle: String {
        switch target {
        case .inbox:
            "Inbox"
        case .jobTask(let jobID):
            store.jobs.first(where: { $0.id == jobID })?.title ?? "Job"
        case .project(_, let projectID):
            store.projectContexts.first(where: { $0.project.id == projectID })?.project.displayTitle ?? "Project"
        }
    }

    private func typeChip(for energy: TaskEnergy) -> some View {
        let jobTint = targetMenuTint
        return Button {
            selectedEnergy = energy
        } label: {
            Text(energy.shortTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(selectedEnergy == energy ? TurboTheme.ink : TurboTheme.mutedInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selectedEnergy == energy ? jobTint.opacity(0.12) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(selectedEnergy == energy ? jobTint.opacity(0.32) : TurboTheme.divider, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .trainingWheelsTooltip(energy.title)
    }

    private func syncQuickCreateTarget() {
        switch target {
        case .inbox:
            break
        case .jobTask(let jobID):
            if !store.jobs.contains(where: { $0.id == jobID }) {
                target = defaultQuickCreateTarget()
            }
        case .project(let jobID, let projectID):
            let ok = store.projectContexts.contains { $0.jobID == jobID && $0.project.id == projectID }
            if !ok {
                target = defaultQuickCreateTarget()
            }
        }
    }

    private func defaultQuickCreateTarget() -> NowQuickCreateTarget {
        .inbox
    }

    private func createTask() {
        guard canCreate else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case .inbox:
            store.addTask(
                title: trimmed,
                status: .queued,
                energy: selectedEnergy,
                cadence: .oneOff,
                isScheduledNow: scheduleForNow,
                repeatEveryMinutes: nil,
                kpiTarget: nil,
                kpiUnit: nil,
                jobID: nil,
                projectID: nil
            )
        case .jobTask(let jobID):
            store.addTask(
                title: trimmed,
                status: .queued,
                energy: selectedEnergy,
                cadence: .oneOff,
                isScheduledNow: scheduleForNow,
                repeatEveryMinutes: nil,
                kpiTarget: nil,
                kpiUnit: nil,
                jobID: jobID,
                projectID: nil
            )
        case .project(let jobID, let projectID):
            store.addTask(
                title: trimmed,
                status: .queued,
                energy: selectedEnergy,
                cadence: .oneOff,
                isScheduledNow: scheduleForNow,
                repeatEveryMinutes: nil,
                kpiTarget: nil,
                kpiUnit: nil,
                jobID: jobID,
                projectID: projectID
            )
        }

        title = ""
        isTitleFocused = true
    }
}

private enum NowBoardMode: String, CaseIterable, Identifiable {
    case list
    case tree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            "List"
        case .tree:
            "Tree"
        }
    }

    var symbol: String {
        switch self {
        case .list:
            "list.bullet"
        case .tree:
            "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

private struct TodayScopeBar: View {
    @EnvironmentObject private var store: TurboTaskStore

    let weekdayTitle: String
    let dateTitle: String
    let visibleJobs: [Job]
    let visibleProjects: [ProjectContext]
    let availableJobChoices: [Job]
    let availableProjectChoices: [ProjectContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Today")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)
                    Text(dateTitle)
                        .font(.subheadline)
                        .foregroundStyle(TurboTheme.mutedInk)
                    Spacer()
                }
            }

            Text("Chips filter the list below. Remove with the X; add again with +. (Tasks remain on Now until you edit them.)")
                .font(.caption2)
                .foregroundStyle(TurboTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ScopeRail(
                label: "Jobs",
                addMenuTitle: "Add Job",
                chips: visibleJobs.map { job in
                    ScopeChipModel(
                        id: job.id,
                        title: job.title,
                        subtitle: nil,
                        tint: job.palette.color
                    )
                },
                addChoices: availableJobChoices.map { job in
                    ScopeMenuChoice(id: job.id, title: job.title, subtitle: "\(job.projects.count) projects", tint: job.palette.color)
                },
                onAdd: { id in store.pinNowJob(id) },
                onRemove: { id in store.removeJobFromNowScope(id) }
            )

            ScopeRail(
                label: "Projects",
                addMenuTitle: "Add Project",
                chips: visibleProjects.map { context in
                    ScopeChipModel(
                        id: context.project.id,
                        title: context.project.displayTitle,
                        subtitle: visibleJobs.count > 1 ? context.jobTitle : nil,
                        tint: context.jobColor
                    )
                },
                addChoices: availableProjectChoices.map { context in
                    ScopeMenuChoice(
                        id: context.project.id,
                        title: context.project.displayTitle,
                        subtitle: context.jobTitle,
                        tint: context.jobColor
                    )
                },
                onAdd: { id in store.pinNowProject(id) },
                onRemove: { id in store.removeProjectFromNowScope(id) }
            )
        }
        .padding(.top, 2)
    }
}

private struct ScopeChipModel: Identifiable {
    let id: UUID
    let title: String
    var subtitle: String? = nil
    let tint: Color
}

private struct ScopeMenuChoice: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let tint: Color
}

private struct ScopeRail: View {
    let label: String
    let addMenuTitle: String
    let chips: [ScopeChipModel]
    let addChoices: [ScopeMenuChoice]
    let onAdd: (UUID) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 52, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if chips.isEmpty {
                        Text("None")
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk.opacity(0.85))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(chips) { chip in
                            ScopeChip(chip: chip, onRemove: {
                                onRemove(chip.id)
                            })
                        }
                    }
                }
            }

            Menu {
                if addChoices.isEmpty {
                    Text("Nothing else to add")
                } else {
                    ForEach(addChoices) { choice in
                        Button {
                            onAdd(choice.id)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title)
                                    Text(choice.subtitle)
                                }
                            } icon: {
                                Circle()
                                    .fill(choice.tint)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
            label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(TurboTheme.divider, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .trainingWheelsTooltip(addMenuTitle)
        }
    }
}

private struct ScopeChip: View {
    let chip: ScopeChipModel
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(chip.tint)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(chip.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
                if let sub = chip.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            .buttonStyle(.plain)
            .trainingWheelsTooltip("Hide from Today scope (add again with +)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(TurboTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(TurboTheme.divider, lineWidth: 1)
                )
        )
    }
}

private struct ReturningLaterCard: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    let tasks: [TaskContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Returning later")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tasks) { context in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.task.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TurboTheme.ink)
                                .lineLimit(2)
                            Text(nextReturnText(for: context.task))
                                .font(.caption2)
                                .foregroundStyle(TurboTheme.mutedInk)
                                .lineLimit(2)
                        }
                        .frame(width: 200, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(TurboTheme.nestedCardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(TurboTheme.divider, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nextReturnText(for task: Task) -> String {
        guard let nextAvailableAt = task.nextAvailableAt else { return "Waiting for the next cycle." }
        return "Back \(Self.relativeFormatter.localizedString(for: nextAvailableAt, relativeTo: .now))"
    }
}

private struct ListBoard: View {
    @EnvironmentObject private var store: TurboTaskStore

    let tasks: [TaskContext]
    let onEditTask: (TaskContext) -> Void

    @State private var draggedTaskID: UUID?
    @State private var dropTargetTaskID: UUID?

    private var openTasks: [TaskContext] {
        tasks.filter { $0.task.status != .done }
    }

    private var doneTasks: [TaskContext] {
        tasks.filter { $0.task.status == .done }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if tasks.isEmpty {
                listBlockHeader(title: "Tasks", trailing: "0")
                listOpenCard {
                    Text("No tasks in this scope.")
                        .font(.subheadline)
                        .foregroundStyle(TurboTheme.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                }
            } else {
                if !openTasks.isEmpty {
                    listBlockHeader(title: "Tasks", trailing: "\(openTasks.count) open")
                    listOpenCard {
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, context in
                                    nowRow(context, showDividerBelow: index < openTasks.count - 1)
                                }
                            }
                            if doneTasks.isEmpty {
                                listEndDropOverlay()
                            }
                        }
                    }
                } else {
                    listBlockHeader(title: "Tasks", trailing: "No open tasks")
                }

                if !doneTasks.isEmpty {
                    listBlockHeader(title: "Done", trailing: "\(doneTasks.count) finished")
                    listDoneCard {
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                ForEach(Array(doneTasks.enumerated()), id: \.element.id) { index, context in
                                    nowRow(context, showDividerBelow: index < doneTasks.count - 1)
                                }
                            }
                            listEndDropOverlay()
                        }
                    }
                }
            }
        }
    }

    private func listBlockHeader(title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
            Spacer()
            Text(trailing)
                .font(.caption.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.bottom, 2)
    }

    private func listOpenCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TurboTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TurboTheme.cardStroke, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func listDoneCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TurboTheme.nestedCardFill.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TurboTheme.cardStroke.opacity(0.65), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Sits over the bottom of the list (no extra blank space below the last row).
    private func listEndDropOverlay() -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onDrop(
                of: nowDragUTTypes,
                delegate: NowTaskEndDropDelegate(draggedTaskID: $draggedTaskID) { id in
                    store.reorderNowTaskToEnd(id)
                }
            )
    }

    @ViewBuilder
    private func nowRow(_ context: TaskContext, showDividerBelow: Bool) -> some View {
        Group {
            NowTaskBlock(
                context: context,
                draggedTaskID: $draggedTaskID,
                dropTargetTaskID: $dropTargetTaskID,
                onEditTask: onEditTask,
                onMoveBefore: { movingTaskID in
                    store.reorderNowTask(movingTaskID, before: context.task.id)
                }
            )
            .environmentObject(store)

            if showDividerBelow {
                Rectangle()
                    .fill(TurboTheme.divider)
                    .frame(height: 1)
            }
        }
    }
}

private struct NowTreeWithDoneSection: View {
    @EnvironmentObject private var store: TurboTaskStore

    let openTasks: [TaskContext]
    let doneTasks: [TaskContext]
    let treeGroups: [[TaskContext]]
    let onEditTask: (TaskContext) -> Void

    @State private var draggedTaskID: UUID?
    @State private var dropTargetTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if openTasks.isEmpty && doneTasks.isEmpty {
                Text("No tasks yet.")
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .padding(.top, 4)
            } else {
                if !openTasks.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tasks")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("\(openTasks.count) open")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                            .monospacedDigit()
                    }
                    .padding(.bottom, 2)

                    TreeBoard(groups: treeGroups, onEditTask: onEditTask)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TurboTheme.cardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TurboTheme.cardStroke, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !doneTasks.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tasks")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("No open tasks")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                    }
                    .padding(.bottom, 2)
                }

                if !doneTasks.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Done")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("\(doneTasks.count) finished")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                            .monospacedDigit()
                    }
                    .padding(.bottom, 2)

                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            ForEach(Array(doneTasks.enumerated()), id: \.element.id) { index, context in
                                Group {
                                    NowTaskBlock(
                                        context: context,
                                        draggedTaskID: $draggedTaskID,
                                        dropTargetTaskID: $dropTargetTaskID,
                                        onEditTask: onEditTask,
                                        onMoveBefore: { movingTaskID in
                                            store.reorderNowTask(movingTaskID, before: context.task.id)
                                        }
                                    )
                                    .environmentObject(store)

                                    if index < doneTasks.count - 1 {
                                        Rectangle()
                                            .fill(TurboTheme.divider)
                                            .frame(height: 1)
                                    }
                                }
                            }
                        }

                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: nowDragUTTypes,
                                delegate: NowTaskEndDropDelegate(draggedTaskID: $draggedTaskID) { id in
                                    store.reorderNowTaskToEnd(id)
                                }
                            )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(TurboTheme.nestedCardFill.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(TurboTheme.cardStroke.opacity(0.65), lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct TreeBoard: View {
    let groups: [[TaskContext]]
    let onEditTask: (TaskContext) -> Void

    @State private var draggedTaskID: UUID?
    @State private var dropTargetTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                TreeBundleRow(
                    group: group,
                    draggedTaskID: $draggedTaskID,
                    dropTargetTaskID: $dropTargetTaskID,
                    onEditTask: onEditTask
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TreeBundleRow: View {
    let group: [TaskContext]
    @Binding var draggedTaskID: UUID?
    @Binding var dropTargetTaskID: UUID?
    let onEditTask: (TaskContext) -> Void

    var body: some View {
        Group {
            if group.count == 1, let context = group.first {
                TreeMiniTaskNode(
                    context: context,
                    layout: .single,
                    draggedTaskID: $draggedTaskID,
                    dropTargetTaskID: $dropTargetTaskID,
                    onEditTask: onEditTask
                )
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            } else if !group.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Spacer(minLength: 0)
                    ForEach(group) { context in
                        TreeMiniTaskNode(
                            context: context,
                            layout: .bundleColumn,
                            draggedTaskID: $draggedTaskID,
                            dropTargetTaskID: $dropTargetTaskID,
                            onEditTask: onEditTask
                        )
                        .frame(minWidth: 200, maxWidth: 272)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct TreeMiniTaskNode: View {
    @EnvironmentObject private var store: TurboTaskStore

    enum Layout {
        case single
        case bundleColumn
    }

    let context: TaskContext
    let layout: Layout
    @Binding var draggedTaskID: UUID?
    @Binding var dropTargetTaskID: UUID?
    let onEditTask: (TaskContext) -> Void

    private var isSelected: Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private var rowFlashActive: Bool {
        store.nowRowFlashTaskID == context.task.id
    }

    private var metaLine: String {
        var parts: [String] = [context.task.energy.shortTitle]
        if !context.projectTitle.isEmpty {
            parts.append(context.projectTitle)
        }
        if let badge = context.task.cadenceBadge {
            parts.append(badge)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.45))
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    draggedTaskID = context.task.id
                    return NSItemProvider(object: context.task.id.uuidString as NSString)
                } preview: {
                    Text(context.task.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(2)
                        .frame(maxWidth: layout == .single ? 400 : 240, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(TurboTheme.cardFill)
                                .shadow(color: TurboTheme.shadow, radius: 6, y: 3)
                        )
                }
                .accessibilityLabel("Reorder")

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(context.jobColor)
                .frame(width: rowFlashActive ? 3 : 2, height: 30)
                .opacity(context.task.status == .done ? 0.35 : 0.95)

            TaskStatusRowIndicator(status: context.task.status, jobColor: context.jobColor, diameter: 15)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(context.task.status == .done ? TurboTheme.mutedInk : TurboTheme.ink)
                        .strikethrough(context.task.status == .done, color: TurboTheme.mutedInk.opacity(0.45))
                        .multilineTextAlignment(.leading)
                        .lineLimit(layout == .single ? 4 : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk.opacity(0.88))
                            .lineLimit(layout == .single ? 2 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if !context.task.toolBundleIDs.isEmpty {
                    TaskToolsIconRow(bundleIDs: context.task.toolBundleIDs, iconSize: 15, maxIcons: 6)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, layout == .single ? 11 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFlashActive ? TurboTheme.rowSelected : TurboTheme.nestedCardFill.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            dropTargetTaskID == context.task.id
                                ? TurboTheme.ink.opacity(0.4)
                                : (rowFlashActive ? context.jobColor.opacity(0.35) : TurboTheme.cardStroke.opacity(0.55)),
                            lineWidth: dropTargetTaskID == context.task.id ? 2 : 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(context.task.title). \(context.jobTitle). \(context.task.status.title). \(metaLine)")
        .onDrop(
            of: nowDragUTTypes,
            delegate: NowTaskDropDelegate(
                targetTaskID: context.task.id,
                draggedTaskID: $draggedTaskID,
                dropTargetTaskID: $dropTargetTaskID,
                onMoveBefore: { movingTaskID in
                    store.reorderNowTask(movingTaskID, before: context.task.id)
                }
            )
        )
        .onTapGesture {
            store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
        }
        .onTapGesture(count: 2) {
            onEditTask(context)
        }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: { onEditTask(context) })
                .environmentObject(store)
        }
        .trainingWheelsTooltip("↑↓←→ change selection · Return starts · ⌘↩ start · ⌘P pause · ⌘D done · Right-click for more")
    }
}

private struct NowTaskBlock: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    var compact = false
    @Binding var draggedTaskID: UUID?
    @Binding var dropTargetTaskID: UUID?
    let onEditTask: (TaskContext) -> Void
    let onMoveBefore: (UUID) -> Void

    @State private var isHovering = false

    private var isSelected: Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private var rowFlashActive: Bool {
        store.nowRowFlashTaskID == context.task.id
    }

    private var metaLine: String {
        var parts: [String] = []
        if !context.projectTitle.isEmpty {
            parts.append(context.projectTitle)
        }
        if let badge = context.task.cadenceBadge {
            parts.append(badge)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dragHandle
                .opacity(isHovering || rowFlashActive ? 0.5 : 0.2)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(context.jobColor)
                .frame(width: rowFlashActive || isHovering ? 3 : 2, height: 36)
                .opacity(context.task.status == .done ? 0.35 : 0.95)

            TaskStatusRowIndicator(status: context.task.status, jobColor: context.jobColor, diameter: 17)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.task.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(context.task.status == .done ? TurboTheme.mutedInk : TurboTheme.ink)
                            .strikethrough(context.task.status == .done, color: TurboTheme.mutedInk.opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .lineLimit(compact ? 2 : 2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(.caption2)
                                .foregroundStyle(TurboTheme.mutedInk.opacity(0.88))
                                .lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !context.task.toolBundleIDs.isEmpty {
                        TaskToolsIconRow(bundleIDs: context.task.toolBundleIDs, iconSize: 17, maxIcons: 7)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 4)

                    Text(context.task.energy.shortTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(context.task.energy.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(context.task.energy.accent.opacity(0.14)))
                        .fixedSize()
                        .accessibilityLabel("Type: \(context.task.energy.title)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                taskStatusMenu
                    .opacity(isHovering || isSelected || rowFlashActive ? 1 : 0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill)
        .overlay {
            if dropTargetTaskID == context.task.id {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(TurboTheme.ink.opacity(0.35), lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Arrow keys change selection. Return starts the task. Command shortcuts: Return start, P pause, D done. Right-click for more.")
        .onDrop(
            of: nowDragUTTypes,
            delegate: NowTaskDropDelegate(
                targetTaskID: context.task.id,
                draggedTaskID: $draggedTaskID,
                dropTargetTaskID: $dropTargetTaskID,
                onMoveBefore: onMoveBefore
            )
        )
        .onHover { isHovering = $0 }
        .onTapGesture {
            store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id))
        }
        .onTapGesture(count: 2) {
            onEditTask(context)
        }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: { onEditTask(context) })
                .environmentObject(store)
        }
        .trainingWheelsTooltip("↑↓←→ selection · Return start · ⌘↩ start · ⌘P pause · ⌘D done · Right-click for more")
    }

    private var accessibilitySummary: String {
        let meta = metaLine.isEmpty ? "" : " \(metaLine)"
        return "\(context.task.title). \(context.jobTitle). \(context.task.energy.title). Status \(context.task.status.title).\(meta)"
    }

    private var rowFill: Color {
        if rowFlashActive {
            return TurboTheme.rowSelected
        }
        if isHovering {
            return TurboTheme.rowHover
        }
        return Color.clear
    }

    private var dragHandle: some View {
        TaskReorderHandle()
            .onDrag {
                draggedTaskID = context.task.id
                return NSItemProvider(object: context.task.id.uuidString as NSString)
            } preview: {
                Text(context.task.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 280, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TurboTheme.cardFill)
                            .shadow(color: TurboTheme.shadow, radius: 8, y: 4)
                    )
            }
            .trainingWheelsTooltip("Drag to reorder on Now")
    }

    private var taskStatusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    guard context.task.status != status else { return }
                    store.setTaskStatus(context, status: status)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: statusMenuSymbol(status))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(statusMenuIconTint(status))
                            .frame(width: 16, alignment: .center)
                        Text(status.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if context.task.status == status {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(context.jobColor)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: statusMenuSymbol(context.task.status))
                    .font(.system(size: 10, weight: .semibold))
                Text(statusShortLabel(context.task.status))
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.75))
            }
            .foregroundStyle(statusPillForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(statusPillFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(statusPillStroke, lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .trainingWheelsTooltip("Set status: queued, active, paused, waiting, done")
        .accessibilityLabel("Status: \(context.task.status.title)")
        .accessibilityHint("Opens a menu to choose Not Started, In Progress, Waiting, Paused, or Done")
    }

    private var statusPillForeground: Color {
        switch context.task.status {
        case .done:
            TurboTheme.mutedInk
        case .active:
            context.jobColor
        default:
            context.task.status.accent
        }
    }

    private var statusPillFill: Color {
        switch context.task.status {
        case .done:
            TurboTheme.nestedCardFill.opacity(0.9)
        case .queued:
            TurboTheme.mutedInk.opacity(0.06)
        case .active:
            context.jobColor.opacity(0.12)
        default:
            context.task.status.accent.opacity(0.12)
        }
    }

    private var statusPillStroke: Color {
        switch context.task.status {
        case .done:
            TurboTheme.divider
        case .queued:
            TurboTheme.divider
        case .active:
            context.jobColor.opacity(0.32)
        default:
            context.task.status.accent.opacity(0.28)
        }
    }

    private func statusMenuIconTint(_ status: TaskStatus) -> Color {
        if status == .active {
            return context.jobColor
        }
        return status.accent
    }

    private func statusShortLabel(_ status: TaskStatus) -> String {
        switch status {
        case .queued:
            "Open"
        case .active:
            "Active"
        case .waiting:
            "Waiting"
        case .paused:
            "Paused"
        case .done:
            "Done"
        }
    }

    private func statusMenuSymbol(_ status: TaskStatus) -> String {
        switch status {
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

private struct NowTaskDropDelegate: DropDelegate {
    let targetTaskID: UUID
    @Binding var draggedTaskID: UUID?
    @Binding var dropTargetTaskID: UUID?
    let onMoveBefore: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: nowDragUTTypes)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID, draggedTaskID != targetTaskID else { return }
        dropTargetTaskID = targetTaskID
    }

    func dropExited(info: DropInfo) {
        if dropTargetTaskID == targetTaskID {
            dropTargetTaskID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetTaskID = nil
        let providers = info.itemProviders(for: nowDragUTTypes)
        guard let provider = providers.first else {
            draggedTaskID = nil
            return false
        }
        let target = targetTaskID
        let move = onMoveBefore
        _ = provider.loadObject(ofClass: NSString.self, completionHandler: { reading, _ in
            DispatchQueue.main.async {
                defer { draggedTaskID = nil }
                let str = (reading as? NSString) as String?
                guard let str, let id = UUID(uuidString: str.trimmingCharacters(in: .whitespacesAndNewlines)),
                      id != target else { return }
                move(id)
            }
        })
        return true
    }
}

private struct NowTaskEndDropDelegate: DropDelegate {
    @Binding var draggedTaskID: UUID?
    let onMoveToEnd: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: nowDragUTTypes) && draggedTaskID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: nowDragUTTypes)
        guard let provider = providers.first else {
            draggedTaskID = nil
            return false
        }
        let end = onMoveToEnd
        _ = provider.loadObject(ofClass: NSString.self, completionHandler: { reading, _ in
            DispatchQueue.main.async {
                defer { draggedTaskID = nil }
                let str = (reading as? NSString) as String?
                guard let str, let id = UUID(uuidString: str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                end(id)
            }
        })
        return true
    }
}

private struct TaskReorderHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(TurboTheme.mutedInk)
            .frame(width: 16, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder")
    }
}
