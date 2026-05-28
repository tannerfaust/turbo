//
//  NowView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Shared mutable drag state passed by reference to all drop delegates so they always see current values.
private final class NowDragState: ObservableObject {
    @Published var draggedID: UUID?
    @Published var hoverTargetID: UUID?
    @Published var hoverIsEnd = false

    func reset() {
        draggedID = nil
        hoverTargetID = nil
        hoverIsEnd = false
    }
}

private struct NowDropLine: View {
    var body: some View {
        Rectangle()
            .fill(TurboTheme.accent)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum NowScrollSpace {
    static let name = "NowScrollSpace"
}

private struct NowTaskFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct NowTaskFrameReporter: ViewModifier {
    let taskID: UUID

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NowTaskFramePreferenceKey.self,
                    value: [taskID: proxy.frame(in: .named(NowScrollSpace.name))]
                )
            }
        )
    }
}

private extension View {
    func nowTaskFrameReporter(taskID: UUID) -> some View {
        modifier(NowTaskFrameReporter(taskID: taskID))
    }
}

/// Mutable flags read from the key-event monitor (must be a reference type).
private final class NowKeyboardGate {
    var taskEditorOpen = false
    var quickCreateExpanded = false
    /// When quick add is open, ⌘T calls this instead of opening the task composer.
    var toggleQuickCreateScheduleForNow: (() -> Void)?
}

struct NowView: View {
    @EnvironmentObject private var store: TurboTaskStore

    @AppStorage("now_list_grouping_mode") private var listGroupingRawValue = NowListGroupingMode.none.rawValue
    @State private var viewMode: NowBoardMode = .list
    @State private var editingTask: TaskContext?
    @State private var quickCreateExpanded = false
    /// Used when creating from the inline quick-add bar (⌘T while bar is open toggles this).
    @State private var quickCreateScheduleForNow = true
    @State private var keyboardGate = NowKeyboardGate()
    @State private var localKeyMonitor: Any?
    @State private var localScrollMonitor: Any?
    @State private var visibleTaskFrames: [UUID: CGRect] = [:]
    @State private var pendingSelectionRevealAnimated: Bool?

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

    private var listGrouping: NowListGroupingMode {
        NowListGroupingMode(rawValue: listGroupingRawValue) ?? .none
    }

    private var listGroupingBinding: Binding<NowListGroupingMode> {
        Binding(
            get: { listGrouping },
            set: { listGroupingRawValue = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Now")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(TurboTheme.ink)
                                Text("\(weekdayTitle) · \(dateTitle)")
                                    .font(.subheadline)
                                    .foregroundStyle(TurboTheme.mutedInk)
                            }
                            Spacer(minLength: 8)
                            Picker("View", selection: $viewMode) {
                                ForEach(NowBoardMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: 148)
                            .trainingWheelsTooltip("List vs tree · ⇧⌘L")

                            Picker("Group", selection: listGroupingBinding) {
                                ForEach(NowListGroupingMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 132)
                            .disabled(viewMode != .list)
                            .help("Optional grouping for the list view.")
                            .trainingWheelsTooltip("Grouping for list view · ⌥⌘0 off · ⌥⌘J jobs · ⌥⌘G jobs + projects")
                        }

                        TodayScopeBar(
                            visibleJobs: store.visibleNowJobs,
                            visibleProjects: store.visibleNowProjects,
                            availableJobChoices: availableJobChoices,
                            availableProjectChoices: availableProjectChoices
                        )
                        .environmentObject(store)

                        if !upcomingRepeatables.isEmpty {
                            ReturningLaterCard(tasks: upcomingRepeatables, onEditTask: { editingTask = $0 })
                                .environmentObject(store)
                        }

                        NowQuickCreateBar(isExpanded: $quickCreateExpanded, scheduleForNow: $quickCreateScheduleForNow)
                            .environmentObject(store)

                        TrainingWheelsHint(text: "⌘N or ⇧⌘A toggles quick add · Esc closes · With the bar open, ⌘T toggles Schedule for Now.")
                            .padding(.top, -2)

                        let scoped = store.scopedNowTasks
                        switch viewMode {
                        case .list:
                            ListBoard(
                                tasks: scoped,
                                grouping: listGrouping,
                                onEditTask: { editingTask = $0 }
                            )
                            .environmentObject(store)
                        case .tree:
                            NowTreeWithDoneSection(
                                openTasks: scoped.filter { $0.task.status != .done },
                                doneTasks: scoped.filter { $0.task.status == .done },
                                treeGroups: store.nowTreeGroups,
                                onEditTask: { editingTask = $0 }
                            )
                            .environmentObject(store)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: NowScrollSpace.name)
                .scrollIndicators(.hidden)
                .onAppear {
                    keyboardGate.taskEditorOpen = editingTask != nil
                    keyboardGate.quickCreateExpanded = quickCreateExpanded
                    keyboardGate.toggleQuickCreateScheduleForNow = { quickCreateScheduleForNow.toggle() }
                    installNowLocalKeyMonitor()
                    installNowLocalScrollMonitor()
                    _Concurrency.Task { @MainActor in
                        store.ensureSelection()
                        requestSelectionReveal(animated: false)
                        flushPendingSelectionReveal(using: proxy, viewportHeight: viewport.size.height)
                    }
                }
                .onDisappear {
                    removeNowLocalKeyMonitor()
                    removeNowLocalScrollMonitor()
                }
                .onPreferenceChange(NowTaskFramePreferenceKey.self) { frames in
                    visibleTaskFrames = frames
                    flushPendingSelectionReveal(using: proxy, viewportHeight: viewport.size.height)
                }
                .onChange(of: editingTask) { _, newValue in
                    keyboardGate.taskEditorOpen = newValue != nil
                }
                .onChange(of: quickCreateExpanded) { _, expanded in
                    keyboardGate.quickCreateExpanded = expanded
                }
                .onChange(of: store.selection) { _, _ in
                    flushPendingSelectionReveal(using: proxy, viewportHeight: viewport.size.height)
                }
                .onChange(of: store.nowShortcutAction) { _, action in
                    guard let action else { return }
                    _Concurrency.Task { @MainActor in
                        store.clearNowShortcutAction()
                        switch action {
                        case .focusQuickAdd:
                            quickCreateExpanded.toggle()
                        case .toggleViewMode:
                            viewMode = viewMode == .list ? .tree : .list
                        case .setListGrouping(let grouping):
                            listGroupingRawValue = grouping.rawValue
                        case .openEditorForSelection:
                            openEditorForSelection()
                        case .startSelectedTask:
                            applyToSelectedTask { store.setTaskStatus($0, status: .active) }
                        case .pauseSelectedTask:
                            applyToSelectedTask { store.setTaskStatus($0, status: .paused) }
                        case .markSelectedDone:
                            requestSelectionReveal(animated: true)
                            applyToSelectedTask { store.setTaskStatus($0, status: .done) }
                        case .markSelectedWaiting:
                            applyToSelectedTask { store.setTaskStatus($0, status: .waiting) }
                        }
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

    private func scrollSelectionIntoView(
        using proxy: ScrollViewProxy,
        viewportHeight: CGFloat,
        animated: Bool = true
    ) -> Bool {
        guard store.selectedScreen == .now else { return true }
        guard case let .task(jobID, projectID, taskID) = store.selection else { return true }
        let isVisibleNowTask = store.scopedNowTasks.contains {
            $0.task.id == taskID && $0.jobID == jobID && $0.projectID == projectID
        }
        guard isVisibleNowTask else { return true }
        guard let frame = visibleTaskFrames[taskID], viewportHeight > 1 else { return false }

        let topMargin: CGFloat = 12
        let bottomMargin: CGFloat = 18
        guard frame.minY < topMargin || frame.maxY > viewportHeight - bottomMargin else { return true }
        let anchor: UnitPoint = frame.minY < topMargin ? .top : .bottom

        _Concurrency.Task { @MainActor in
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(taskID, anchor: anchor)
                }
            } else {
                proxy.scrollTo(taskID, anchor: anchor)
            }
        }
        return true
    }

    private func requestSelectionReveal(animated: Bool) {
        pendingSelectionRevealAnimated = animated
    }

    private func cancelSelectionReveal() {
        pendingSelectionRevealAnimated = nil
    }

    private func flushPendingSelectionReveal(using proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard let animated = pendingSelectionRevealAnimated else { return }
        guard scrollSelectionIntoView(using: proxy, viewportHeight: viewportHeight, animated: animated) else { return }
        pendingSelectionRevealAnimated = nil
    }

    private func installNowLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        let gate = keyboardGate
        let st = store
        let requestSelectionReveal = { self.requestSelectionReveal(animated: true) }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let commandDown = event.modifierFlags.contains(.command)
            let consume = MainActor.assumeIsolated {
                NowLocalKeyRouter.shouldConsumeKey(
                    keyCode: keyCode,
                    commandDown: commandDown,
                    store: st,
                    gate: gate,
                    requestSelectionReveal: requestSelectionReveal
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

    private func installNowLocalScrollMonitor() {
        guard localScrollMonitor == nil else { return }
        let st = store
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                guard st.selectedScreen == .now else { return }
                cancelSelectionReveal()
                if case .task = st.selection {
                    st.select(nil)
                }
            }
            return event
        }
    }

    private func removeNowLocalScrollMonitor() {
        if let monitor = localScrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        localScrollMonitor = nil
    }
}

// MARK: - Local keys (arrows + return) on main thread

private enum NowLocalKeyRouter {
    @MainActor
    static func shouldConsumeKey(
        keyCode: UInt16,
        commandDown: Bool,
        store: TurboTaskStore,
        gate: NowKeyboardGate,
        requestSelectionReveal: () -> Void
    ) -> Bool {
        guard store.selectedScreen == .now else { return false }
        guard !gate.taskEditorOpen else { return false }
        guard store.composer == nil else { return false }

        if gate.quickCreateExpanded, commandDown, keyCode == 17 {
            gate.toggleQuickCreateScheduleForNow?()
            return true
        }

        guard !gate.quickCreateExpanded else { return false }
        guard !textInputHasFocus() else { return false }

        switch keyCode {
        case 126, 123:
            requestSelectionReveal()
            store.moveNowSelection(-1)
            return true
        case 125, 124:
            requestSelectionReveal()
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
        VStack(alignment: .leading, spacing: 6) {
            plusButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        TextField("Create task\u{2026}", text: $title)
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
                            .trainingWheelsTooltip("Add to Now when created \u{00B7} \u{2318}T while this bar is open")

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
                        .trainingWheelsTooltip("Create task \u{00B7} Return")
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
        .onChange(of: store.jobs.count) {
            syncQuickCreateTarget()
        }
        .onChange(of: store.nowPinnedProjectIDs) {
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
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(TurboTheme.divider.opacity(0.9), lineWidth: 1)
                    )
                Text(isExpanded ? "Close" : "Add")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Close quick add (Esc, \u{2318}N)" : "Quick-add a task (\u{2318}N)")
        .trainingWheelsTooltip(isExpanded ? "Close quick add \u{00B7} \u{2318}N \u{00B7} \u{21E7}\u{2318}A \u{00B7} Esc" : "Open quick add \u{00B7} \u{2318}N \u{00B7} \u{21E7}\u{2318}A")
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
            TurboTheme.inboxAccent
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
                title: trimmed, status: .queued, energy: selectedEnergy, cadence: .oneOff,
                isScheduledNow: scheduleForNow, repeatEveryMinutes: nil,
                kpiTarget: nil, kpiRoundsRemaining: nil, jobID: nil, projectID: nil
            )
        case .jobTask(let jobID):
            store.addTask(
                title: trimmed, status: .queued, energy: selectedEnergy, cadence: .oneOff,
                isScheduledNow: scheduleForNow, repeatEveryMinutes: nil,
                kpiTarget: nil, kpiRoundsRemaining: nil, jobID: jobID, projectID: nil
            )
        case .project(let jobID, let projectID):
            store.addTask(
                title: trimmed, status: .queued, energy: selectedEnergy, cadence: .oneOff,
                isScheduledNow: scheduleForNow, repeatEveryMinutes: nil,
                kpiTarget: nil, kpiRoundsRemaining: nil, jobID: jobID, projectID: projectID
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
        case .list: "List"
        case .tree: "Tree"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .tree: "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

private struct TodayScopeBar: View {
    @EnvironmentObject private var store: TurboTaskStore

    let visibleJobs: [Job]
    let visibleProjects: [ProjectContext]
    let availableJobChoices: [Job]
    let availableProjectChoices: [ProjectContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScopeRail(
                label: "Jobs", addMenuTitle: "Add Job",
                chips: visibleJobs.map { ScopeChipModel(id: $0.id, title: $0.title, tint: $0.palette.color) },
                addChoices: availableJobChoices.map { ScopeMenuChoice(id: $0.id, title: $0.title, subtitle: "\($0.projects.count) projects", tint: $0.palette.color) },
                onAdd: { store.pinNowJob($0) },
                onRemove: { store.removeJobFromNowScope($0) }
            )

            ScopeRail(
                label: "Projects", addMenuTitle: "Add Project",
                chips: visibleProjects.map { ScopeChipModel(id: $0.project.id, title: $0.project.displayTitle, subtitle: visibleJobs.count > 1 ? $0.jobTitle : nil, tint: $0.jobColor) },
                addChoices: availableProjectChoices.map { ScopeMenuChoice(id: $0.project.id, title: $0.project.displayTitle, subtitle: $0.jobTitle, tint: $0.jobColor) },
                onAdd: { store.pinNowProject($0) },
                onRemove: { store.removeProjectFromNowScope($0) }
            )
        }
        .help("Scope filters limit which tasks appear on Now. Remove a chip with \u{00D7}; add with +.")
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
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 56, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if chips.isEmpty {
                        Text("\u{2014}")
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk.opacity(0.55))
                            .padding(.vertical, 2)
                    } else {
                        ForEach(chips) { chip in
                            ScopeChip(chip: chip, onRemove: { onRemove(chip.id) })
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
                                Circle().fill(choice.tint).frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
            label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(TurboTheme.divider.opacity(0.9), lineWidth: 1)
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
            Circle().fill(chip.tint).frame(width: 6, height: 6)

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
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(TurboTheme.cardFill.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(TurboTheme.divider.opacity(0.85), lineWidth: 1)
                )
        )
    }
}

private struct ReturningLaterCard: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    let tasks: [TaskContext]
    let onEditTask: (TaskContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Later")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.9))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tasks) { context in
                        ReturningLaterTaskChip(
                            context: context,
                            returnLine: Self.nextReturnText(for: context.task),
                            onEditTask: onEditTask
                        )
                    }
                }
            }
        }
        .help("Repeatable or KPI tasks waiting for their next cycle. Click to select, double-click to edit, two-finger click for the full menu.")
    }

    private static func nextReturnText(for task: Task) -> String {
        guard let nextAvailableAt = task.nextAvailableAt else { return "Waiting for the next cycle." }
        return "Back \(relativeFormatter.localizedString(for: nextAvailableAt, relativeTo: .now))"
    }
}

private struct ReturningLaterTaskChip: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    let returnLine: String
    let onEditTask: (TaskContext) -> Void

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.task.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(TurboTheme.ink)
                .lineLimit(1)
            Text(returnLine)
                .font(.caption2)
                .foregroundStyle(TurboTheme.mutedInk)
                .lineLimit(1)
        }
        .frame(width: 168, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            chipShape
                .fill(TurboTheme.nestedCardFill.opacity(0.88))
                .overlay(chipShape.stroke(TurboTheme.divider.opacity(0.75), lineWidth: 1))
        )
        .contentShape(chipShape)
        .onTapGesture(count: 2) { onEditTask(context) }
        .onTapGesture { store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)) }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: { onEditTask(context) })
                .environmentObject(store)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.task.title). \(returnLine)")
        .accessibilityHint("Double-click to edit. Two-finger click or Control-click for pin, archive, delete, and more.")
    }
}

private struct NowListSection: Identifiable {
    let id: String
    let title: String?
    let tasks: [TaskContext]
}

private struct NowListJobGroup: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let sections: [NowListSection]
}

private func buildNowListJobGroups(from tasks: [TaskContext], grouping: NowListGroupingMode) -> [NowListJobGroup] {
    guard grouping != .none else { return [] }

    struct JobBucket {
        var title: String
        var tint: Color
        var tasks: [TaskContext]
    }

    var orderedJobKeys: [String] = []
    var jobBuckets: [String: JobBucket] = [:]

    for context in tasks {
        let jobKey = context.jobID?.uuidString ?? "inbox"
        if jobBuckets[jobKey] == nil {
            orderedJobKeys.append(jobKey)
            let title = context.jobTitle.isEmpty ? "Inbox" : context.jobTitle
            jobBuckets[jobKey] = JobBucket(title: title, tint: context.jobColor, tasks: [])
        }
        jobBuckets[jobKey]?.tasks.append(context)
    }

    return orderedJobKeys.compactMap { jobKey in
        guard let bucket = jobBuckets[jobKey] else { return nil }
        let sections = buildNowListSections(from: bucket.tasks, grouping: grouping)
        return NowListJobGroup(id: jobKey, title: bucket.title, tint: bucket.tint, sections: sections)
    }
}

private func buildNowListSections(from tasks: [TaskContext], grouping: NowListGroupingMode) -> [NowListSection] {
    guard grouping == .jobsAndProjects else {
        return [NowListSection(id: "all", title: nil, tasks: tasks)]
    }

    var orderedSectionKeys: [String] = []
    var titlesByKey: [String: String?] = [:]
    var tasksByKey: [String: [TaskContext]] = [:]

    for context in tasks {
        let key = context.projectID?.uuidString ?? "__job__"
        if tasksByKey[key] == nil {
            orderedSectionKeys.append(key)
            titlesByKey[key] = context.projectTitle.isEmpty ? nil : context.projectTitle
            tasksByKey[key] = []
        }
        tasksByKey[key, default: []].append(context)
    }

    return orderedSectionKeys.compactMap { key in
        guard let sectionTasks = tasksByKey[key] else { return nil }
        return NowListSection(id: key, title: titlesByKey[key] ?? nil, tasks: sectionTasks)
    }
}

private struct NowListJobHeader: View {
    let group: NowListJobGroup

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Capsule()
                .fill(group.tint.opacity(0.78))
                .frame(width: 14, height: 3)

            Text(group.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.92))
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct NowListProjectHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(TurboTheme.divider.opacity(0.75))
                .frame(width: 8, height: 1)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.86))
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

// MARK: - List Board (drag-and-drop reorder)

private struct ListBoard: View {
    @EnvironmentObject private var store: TurboTaskStore
    @StateObject private var drag = NowDragState()

    let tasks: [TaskContext]
    let grouping: NowListGroupingMode
    let onEditTask: (TaskContext) -> Void

    private var openTasks: [TaskContext] { tasks.filter { $0.task.status != .done } }
    private var doneTasks: [TaskContext] { tasks.filter { $0.task.status == .done } }
    private var openGroups: [NowListJobGroup] { buildNowListJobGroups(from: openTasks, grouping: grouping) }
    private var doneGroups: [NowListJobGroup] { buildNowListJobGroups(from: doneTasks, grouping: grouping) }

    private func showDividerBelow(in list: [TaskContext], index: Int) -> Bool {
        guard index < list.count - 1 else { return false }
        if drag.draggedID != nil, !drag.hoverIsEnd, drag.hoverTargetID == list[index + 1].id {
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if tasks.isEmpty {
                sectionHeader(title: "Tasks", trailing: "0")
                cardWrap(fill: TurboTheme.cardFill, stroke: TurboTheme.cardStroke) {
                    Text("No tasks in this scope.")
                        .font(.subheadline)
                        .foregroundStyle(TurboTheme.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                }
            } else {
                if !openTasks.isEmpty {
                    sectionHeader(title: "Tasks", trailing: "\(openTasks.count) open")
                    cardWrap(fill: TurboTheme.cardFill, stroke: TurboTheme.cardStroke) {
                        taskColumn(tasks: openTasks, groups: openGroups, isLast: doneTasks.isEmpty)
                    }
                } else {
                    sectionHeader(title: "Tasks", trailing: "No open tasks")
                }

                if !doneTasks.isEmpty {
                    sectionHeader(title: "Done", trailing: "\(doneTasks.count) finished")
                    cardWrap(fill: TurboTheme.nestedCardFill.opacity(0.88), stroke: TurboTheme.cardStroke.opacity(0.65)) {
                        taskColumn(tasks: doneTasks, groups: doneGroups, isLast: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskColumn(tasks: [TaskContext], groups: [NowListJobGroup], isLast: Bool) -> some View {
        VStack(spacing: 0) {
            if grouping == .none {
                taskRows(tasks)
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    if groups.count > 1 || grouping != .none {
                        NowListJobHeader(group: group)
                    }

                    let showProjectHeaders = grouping == .jobsAndProjects && group.sections.count > 1
                    ForEach(group.sections) { section in
                        if showProjectHeaders, let title = section.title {
                            NowListProjectHeader(title: title)
                        }
                        taskRows(section.tasks)
                    }

                    if groupIndex < groups.count - 1 {
                        Color.clear.frame(height: 6)
                    }
                }
            }

            if isLast {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 18)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if drag.draggedID != nil, drag.hoverIsEnd { NowDropLine() }
                    }
                    .onDrop(of: [.text], delegate: NowEndDropDelegate(drag: drag) { movingID in
                        store.reorderNowTaskToEnd(movingID)
                    })
            }
        }
    }

    @ViewBuilder
    private func taskRows(_ list: [TaskContext]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { index, context in
            NowTaskBlock(context: context, drag: drag, onEditTask: onEditTask)
                .environmentObject(store)
                .overlay(alignment: .top) {
                    if drag.draggedID != nil, !drag.hoverIsEnd, drag.hoverTargetID == context.task.id {
                        NowDropLine()
                    }
                }
                .onDrop(of: [.text], delegate: NowRowDropDelegate(rowID: context.task.id, drag: drag) { movingID in
                    store.reorderNowTask(movingID, before: context.task.id)
                })

            if showDividerBelow(in: list, index: index) {
                Rectangle().fill(TurboTheme.divider).frame(height: 1)
            }
        }
    }

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(TurboTheme.ink)
            Spacer()
            Text(trailing).font(.caption.weight(.medium)).foregroundStyle(TurboTheme.mutedInk).multilineTextAlignment(.trailing).monospacedDigit()
        }
        .padding(.bottom, 2)
    }

    private func cardWrap<Content: View>(fill: Color, stroke: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Tree view

private struct NowTreeWithDoneSection: View {
    @EnvironmentObject private var store: TurboTaskStore
    @StateObject private var drag = NowDragState()

    let openTasks: [TaskContext]
    let doneTasks: [TaskContext]
    let treeGroups: [[TaskContext]]
    let onEditTask: (TaskContext) -> Void

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
                        Text("Tasks").font(.headline.weight(.semibold)).foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("\(openTasks.count) open").font(.caption.weight(.medium)).foregroundStyle(TurboTheme.mutedInk).monospacedDigit()
                    }
                    .padding(.bottom, 2)

                    TreeBoard(groups: treeGroups, drag: drag, onEditTask: onEditTask)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TurboTheme.cardFill)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TurboTheme.cardStroke, lineWidth: 1))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !doneTasks.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tasks").font(.headline.weight(.semibold)).foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("No open tasks").font(.caption.weight(.medium)).foregroundStyle(TurboTheme.mutedInk)
                    }
                    .padding(.bottom, 2)
                }

                if !doneTasks.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Done").font(.headline.weight(.semibold)).foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Text("\(doneTasks.count) finished").font(.caption.weight(.medium)).foregroundStyle(TurboTheme.mutedInk).monospacedDigit()
                    }
                    .padding(.bottom, 2)

                    VStack(spacing: 0) {
                        ForEach(Array(doneTasks.enumerated()), id: \.element.id) { index, context in
                            NowTaskBlock(context: context, drag: drag, onEditTask: onEditTask)
                                .environmentObject(store)
                                .overlay(alignment: .top) {
                                    if drag.draggedID != nil, !drag.hoverIsEnd, drag.hoverTargetID == context.task.id {
                                        NowDropLine()
                                    }
                                }
                                .onDrop(of: [.text], delegate: NowRowDropDelegate(rowID: context.task.id, drag: drag) { movingID in
                                    store.reorderNowTask(movingID, before: context.task.id)
                                })

                            if index < doneTasks.count - 1 {
                                Rectangle().fill(TurboTheme.divider).frame(height: 1)
                            }
                        }

                        Color.clear.frame(maxWidth: .infinity).frame(height: 18).contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if drag.draggedID != nil, drag.hoverIsEnd { NowDropLine() }
                            }
                            .onDrop(of: [.text], delegate: NowEndDropDelegate(drag: drag) { movingID in
                                store.reorderNowTaskToEnd(movingID)
                            })
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TurboTheme.nestedCardFill.opacity(0.88))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TurboTheme.cardStroke.opacity(0.65), lineWidth: 1))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct TreeBoard: View {
    let groups: [[TaskContext]]
    @ObservedObject var drag: NowDragState
    let onEditTask: (TaskContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                TreeBundleRow(group: group, drag: drag, onEditTask: onEditTask)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TreeBundleRow: View {
    let group: [TaskContext]
    @ObservedObject var drag: NowDragState
    let onEditTask: (TaskContext) -> Void

    var body: some View {
        Group {
            if group.count == 1, let context = group.first {
                TreeMiniTaskNode(context: context, layout: .single, drag: drag, onEditTask: onEditTask)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            } else if !group.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Spacer(minLength: 0)
                    ForEach(group) { context in
                        TreeMiniTaskNode(context: context, layout: .bundleColumn, drag: drag, onEditTask: onEditTask)
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

    enum Layout { case single, bundleColumn }

    let context: TaskContext
    let layout: Layout
    @ObservedObject var drag: NowDragState
    let onEditTask: (TaskContext) -> Void

    private var rowFlashActive: Bool { store.nowRowFlashTaskID == context.task.id }

    private var metaLine: String {
        var parts: [String] = [context.task.energy.shortTitle]
        if !context.projectTitle.isEmpty { parts.append(context.projectTitle) }
        if let badge = context.task.cadenceBadge { parts.append(badge) }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        rowContent
            .overlay(alignment: .top) {
                if drag.draggedID != nil, !drag.hoverIsEnd, drag.hoverTargetID == context.task.id {
                    NowDropLine()
                }
            }
            .onDrop(of: [.text], delegate: NowRowDropDelegate(rowID: context.task.id, drag: drag) { movingID in
                store.reorderNowTask(movingID, before: context.task.id)
            })
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.45))
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    drag.draggedID = context.task.id
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
                        .stroke(rowFlashActive ? context.jobColor.opacity(0.35) : TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .id(context.task.id)
        .nowTaskFrameReporter(taskID: context.task.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(context.task.title). \(context.jobTitle). \(context.task.status.title). \(metaLine)")
        .onTapGesture(count: 2) { onEditTask(context) }
        .onTapGesture { store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)) }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: { onEditTask(context) })
                .environmentObject(store)
        }
        .trainingWheelsTooltip("\u{2191}\u{2193} change selection \u{00B7} \u{21A9} starts \u{00B7} \u{2318}\u{21A9} start \u{00B7} \u{2318}P pause \u{00B7} \u{2318}D done \u{00B7} Right-click for more")
    }
}

// MARK: - Task Row (list mode)

private struct NowTaskBlock: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    var compact = false
    @ObservedObject var drag: NowDragState
    let onEditTask: (TaskContext) -> Void

    @State private var isHovering = false

    private var isSelected: Bool {
        store.selection == .task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)
    }

    private var rowFlashActive: Bool { store.nowRowFlashTaskID == context.task.id }

    private var showsKpiCounter: Bool {
        context.task.cadence == .kpi && context.task.kpiTarget != nil
    }

    private var metaLine: String {
        var parts: [String] = []
        if !context.projectTitle.isEmpty { parts.append(context.projectTitle) }
        if let badge = context.task.cadenceBadge { parts.append(badge) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dragHandle.opacity(isHovering || rowFlashActive ? 0.5 : 0.2)

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

                    if showsKpiCounter {
                        Button {
                            store.adjustKpiCount(context, delta: 1)
                        } label: {
                            HStack(spacing: 4) {
                                Text(context.task.kpiCounterLabel ?? "\(context.task.kpiCount)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(TurboTheme.ink)
                                    .lineLimit(1)

                                Image(systemName: "plus")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(context.jobColor.opacity(0.95))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(context.jobColor.opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .stroke(context.jobColor.opacity(0.24), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Add one to this KPI counter")
                        .accessibilityLabel("Count KPI")
                    }

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
        .contentShape(Rectangle())
        .id(context.task.id)
        .nowTaskFrameReporter(taskID: context.task.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Arrow keys change selection. Return starts the task. Command shortcuts: Return start, P pause, D done. Right-click for more.")
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onEditTask(context) }
        .onTapGesture { store.select(.task(jobID: context.jobID, projectID: context.projectID, taskID: context.task.id)) }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: { onEditTask(context) })
                .environmentObject(store)
        }
        .trainingWheelsTooltip("\u{2191}\u{2193} selection \u{00B7} \u{21A9} start \u{00B7} \u{2318}\u{21A9} start \u{00B7} \u{2318}P pause \u{00B7} \u{2318}D done \u{00B7} Right-click for more")
    }

    private var accessibilitySummary: String {
        let meta = metaLine.isEmpty ? "" : " \(metaLine)"
        return "\(context.task.title). \(context.jobTitle). \(context.task.energy.title). Status \(context.task.status.title).\(meta)"
    }

    private var rowFill: Color {
        if rowFlashActive { return TurboTheme.rowSelected }
        if isHovering { return TurboTheme.rowHover }
        return Color.clear
    }

    private var dragHandle: some View {
        TaskReorderHandle()
            .onDrag {
                drag.draggedID = context.task.id
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
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(statusPillFill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(statusPillStroke, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .trainingWheelsTooltip("Set status: queued, active, paused, waiting, done")
        .accessibilityLabel("Status: \(context.task.status.title)")
        .accessibilityHint("Opens a menu to choose Not Started, In Progress, Waiting, Paused, or Done")
    }

    private var statusPillForeground: Color {
        switch context.task.status {
        case .done: TurboTheme.mutedInk
        case .active: context.jobColor
        default: context.task.status.accent
        }
    }

    private var statusPillFill: Color {
        switch context.task.status {
        case .done: TurboTheme.nestedCardFill.opacity(0.9)
        case .queued: TurboTheme.mutedInk.opacity(0.06)
        case .active: context.jobColor.opacity(0.12)
        default: context.task.status.accent.opacity(0.12)
        }
    }

    private var statusPillStroke: Color {
        switch context.task.status {
        case .done: TurboTheme.divider
        case .queued: TurboTheme.divider
        case .active: context.jobColor.opacity(0.32)
        default: context.task.status.accent.opacity(0.28)
        }
    }

    private func statusMenuIconTint(_ status: TaskStatus) -> Color {
        status == .active ? context.jobColor : status.accent
    }

    private func statusShortLabel(_ status: TaskStatus) -> String {
        switch status {
        case .queued: "Open"
        case .active: "Active"
        case .waiting: "Waiting"
        case .paused: "Paused"
        case .done: "Done"
        }
    }

    private func statusMenuSymbol(_ status: TaskStatus) -> String {
        switch status {
        case .queued: "circle"
        case .active: "play.fill"
        case .waiting: "hourglass"
        case .paused: "pause.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}

// MARK: - Drop Delegates (reference-type drag state for reliability)

private struct NowRowDropDelegate: DropDelegate {
    let rowID: UUID
    let drag: NowDragState
    let onMoveBefore: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        drag.draggedID != nil && drag.draggedID != rowID
    }

    func dropEntered(info: DropInfo) {
        guard let id = drag.draggedID, id != rowID else { return }
        drag.hoverIsEnd = false
        drag.hoverTargetID = rowID
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTargetID == rowID { drag.hoverTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedID, movingID != rowID else {
            drag.reset()
            return false
        }
        drag.reset()
        onMoveBefore(movingID)
        return true
    }
}

private struct NowEndDropDelegate: DropDelegate {
    let drag: NowDragState
    let onMoveToEnd: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.draggedID != nil }

    func dropEntered(info: DropInfo) {
        guard drag.draggedID != nil else { return }
        drag.hoverTargetID = nil
        drag.hoverIsEnd = true
    }

    func dropExited(info: DropInfo) { drag.hoverIsEnd = false }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedID else {
            drag.reset()
            return false
        }
        drag.reset()
        onMoveToEnd(movingID)
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
