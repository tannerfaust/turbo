//
//  SettingsView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TurboTaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    Image("AppLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    TurboPageHeader(title: "Settings")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance")
                        .font(.headline)
                        .foregroundStyle(TurboTheme.ink)

                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { store.themeMode },
                            set: { val in _Concurrency.Task { @MainActor in store.setThemeMode(val) } }
                        )
                    ) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .turboCard()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Workspace")
                            .font(.headline)
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Workspace settings",
                            message: "Default behavior for archiving, the focus card, and where new Now tasks land."
                        )
                    }

                    Stepper(
                        "Daily capacity: \(store.dailyCapacityMinutes) min",
                        value: Binding(
                            get: { store.dailyCapacityMinutes },
                            set: { val in _Concurrency.Task { @MainActor in store.setDailyCapacityMinutes(val) } }
                        ),
                        in: 120...960,
                        step: 15
                    )

                    HStack(spacing: 8) {
                        Text(
                            store.taskAutoArchiveAfterIdleHours == 0
                                ? "Idle auto-archive: Off"
                                : "Idle auto-archive after \(store.taskAutoArchiveAfterIdleHours) h"
                        )
                        .font(.body)
                        .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Idle auto-archive",
                            message: "Incomplete tasks that are not in progress are archived when they have no activity log entries for at least that long. 0 turns this off. Open Archive from the sidebar footer for archived tasks."
                        )
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(
                                get: { store.taskAutoArchiveAfterIdleHours },
                                set: { val in _Concurrency.Task { @MainActor in store.setTaskAutoArchiveAfterIdleHours(val) } }
                            ),
                            in: 0...720,
                            step: 1
                        )
                        .labelsHidden()
                    }

                    HStack(spacing: 8) {
                        Text(
                            store.doneTaskAutoArchiveAfterDays == 0
                                ? "Archive completed tasks: Off"
                                : "Archive completed tasks after \(store.doneTaskAutoArchiveAfterDays) day\(store.doneTaskAutoArchiveAfterDays == 1 ? "" : "s")"
                        )
                        .font(.body)
                        .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Completed task archive",
                            message: "When on, tasks you marked done move to the archive automatically after that many days from the last completion in the activity log. 0 leaves completed tasks in the main lists until you archive them yourself."
                        )
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(
                                get: { store.doneTaskAutoArchiveAfterDays },
                                set: { val in _Concurrency.Task { @MainActor in store.setDoneTaskAutoArchiveAfterDays(val) } }
                            ),
                            in: 0...365,
                            step: 1
                        )
                        .labelsHidden()
                    }

                    HStack(spacing: 8) {
                        Text(
                            store.archivedTaskPurgeAfterDays == 0
                                ? "Auto-delete from archive: Never"
                                : "Auto-delete from archive after \(store.archivedTaskPurgeAfterDays) day\(store.archivedTaskPurgeAfterDays == 1 ? "" : "s")"
                        )
                        .font(.body)
                        .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Archive deletion",
                            message: "Removes archived tasks from the workspace after they have stayed in the archive that long. Completion and focus events remain in Metrics so your charts and totals stay complete."
                        )
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(
                                get: { store.archivedTaskPurgeAfterDays },
                                set: { val in _Concurrency.Task { @MainActor in store.setArchivedTaskPurgeAfterDays(val) } }
                            ),
                            in: 0...3650,
                            step: 1
                        )
                        .labelsHidden()
                    }

                    HStack(spacing: 8) {
                        Text("Show floating focus card")
                            .font(.body)
                            .foregroundStyle(TurboTheme.ink)
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { store.isFocusOverlayVisible },
                                set: { isVisible in
                                    _Concurrency.Task { @MainActor in
                                        if isVisible != store.isFocusOverlayVisible {
                                            store.toggleOverlay()
                                        }
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("New Now tasks")
                                .font(.body)
                                .foregroundStyle(TurboTheme.ink)
                            TurboInfoButton(
                                title: "New Now tasks",
                                message: "Controls where newly created tasks scheduled for Now appear. Top inserts them under any active tasks and above the rest of the list."
                            )
                        }
                        Picker("", selection: Binding(
                            get: { store.newNowTaskPlacement },
                            set: { val in _Concurrency.Task { @MainActor in store.newNowTaskPlacement = val } }
                        )) {
                            ForEach(NewNowTaskPlacement.allCases) { placement in
                                Text(placement.title).tag(placement)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Focus card on")
                                .font(.body)
                                .foregroundStyle(TurboTheme.ink)
                            TurboInfoButton(
                                title: "Focus card presence",
                                message: store.focusOverlayPresenceMode.settingsSubtitle
                            )
                        }
                        Picker("", selection: Binding(
                            get: { store.focusOverlayPresenceMode },
                            set: { val in _Concurrency.Task { @MainActor in store.focusOverlayPresenceMode = val } }
                        )) {
                            ForEach(FocusOverlayPresenceMode.allCases) { mode in
                                Text(mode.settingsTitle).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                    .padding(.top, 4)
                }
                .turboCard()

                DayPlannerCard()
                    .environmentObject(store)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Keyboard & learning")
                            .font(.headline)
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Keyboard & learning",
                            message: "Keyboard behavior, training wheels, and task actions for the currently selected task."
                        )
                    }

                    HStack(spacing: 8) {
                        Text("Show keyboard hints (training wheels)")
                            .font(.body)
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Training wheels",
                            message: "Shows inline hint lines where they exist, plus hover tooltips on buttons and controls."
                        )
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { store.trainingWheelsEnabled },
                                set: { val in _Concurrency.Task { @MainActor in store.trainingWheelsEnabled = val } }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    HStack(spacing: 8) {
                        Text("Arrow keys in search lists")
                            .font(.body)
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Arrow keys in search lists",
                            message: "While a search field is focused, up and down move the highlight and Return selects. Works in Tasks, Fields, Projects, and the app picker."
                        )
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { store.typeaheadListNavigationEnabled },
                                set: { val in _Concurrency.Task { @MainActor in store.typeaheadListNavigationEnabled = val } }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Text("Selected task")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Selected task actions",
                            message: "Same as the Now and Selection menus: Command-Return starts, Command-P pauses, Command-D marks done, Command-Shift-U or Command-Shift-W sets waiting, and Control-Command-1 through 5 sets status. Select a task first."
                        )
                    }

                    Text(taskSelectionStatusLine)
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)
                        .padding(.bottom, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        Button("Start (active)") {
                            store.applyStatusToSelectedTask(.active)
                        }
                        .disabled(store.selectedTaskContext == nil)
                        .trainingWheelsTooltip("Same as ⌘↩ with a task selected")
                        Button("Pause") {
                            store.applyStatusToSelectedTask(.paused)
                        }
                        .disabled(store.selectedTaskContext == nil)
                        .trainingWheelsTooltip("Same as ⌘P")
                        Button("Waiting") {
                            store.applyStatusToSelectedTask(.waiting)
                        }
                        .disabled(store.selectedTaskContext == nil)
                        .trainingWheelsTooltip("Same as ⌘⇧U")
                        Button("Mark done") {
                            store.applyStatusToSelectedTask(.done)
                        }
                        .disabled(store.selectedTaskContext == nil)
                        .trainingWheelsTooltip("Same as ⌘D")
                        Button("Not started") {
                            store.applyStatusToSelectedTask(.queued)
                        }
                        .disabled(store.selectedTaskContext == nil)
                        .trainingWheelsTooltip("Back to queued / not started")
                    }
                    .buttonStyle(.bordered)

                }
                .turboCard()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Shortcut map")
                            .font(.headline)
                            .foregroundStyle(TurboTheme.ink)
                        TurboInfoButton(
                            title: "Shortcut map",
                            message: "These shortcuts also appear in the menu bar. Turn on training wheels to see hover hints on buttons."
                        )
                    }

                    shortcutSection("Navigation") {
                        shortcutRow("⌘1", "Now")
                        shortcutRow("⌘2", "Projects")
                        shortcutRow("⌘3", "Tasks")
                        shortcutRow("⌘4", "Fields")
                        shortcutRow("⌘5", "Metrics")
                        shortcutRow("⌘6", "Battery")
                        shortcutRow("⌘7", "Archive")
                        shortcutRow("⌘,", "Settings")
                    }

                    shortcutSection("Create & capture") {
                        shortcutRow("⌘T", "New task (composer)")
                        shortcutRow("⌘N", "New task on Now (composer, scheduled to Now)")
                        shortcutRow("⇧⌘A", "New task on Now (same as ⌘N)")
                        shortcutRow("⌘⇧P", "New project")
                        shortcutRow("⌘⇧J", "New field")
                    }

                    shortcutSection("Focus & layout") {
                        shortcutRow("⇧⌘F", "Show or hide floating focus card")
                        shortcutRow("⇧⌘L", "Now: toggle list vs tree")
                        shortcutRow("⌘E", "Edit selected task (sheet)")
                    }

                    shortcutSection(
                        "Start, pause, finish (selected task)",
                        info: "Select a task on Now, Tasks, Projects, or Fields first."
                    ) {
                        shortcutRow("Return", "On Now only: start the highlighted task (set to active)")
                        shortcutRow("⌘↩", "Start selected task (any screen)")
                        shortcutRow("⌘P", "Pause selected task")
                        shortcutRow("⌘D", "Mark selected task done")
                        shortcutRow("⌘⇧U", "Set selected task to waiting")
                        shortcutRow("⌘⇧W", "Waiting (same as ⌘⇧U)")
                    }

                    shortcutSection("Selection menu (any screen)") {
                        shortcutRow("⌃⌘1", "Not started")
                        shortcutRow("⌃⌘2", "In progress")
                        shortcutRow("⌃⌘3", "Waiting")
                        shortcutRow("⌃⌘4", "Paused")
                        shortcutRow("⌃⌘5", "Done")
                    }

                    shortcutSection("Task composer (sheet open)") {
                        shortcutRow("⌥⌘1 … ⌥⌘5", "Jump status to Not started / In progress / Waiting / Paused / Done")
                        shortcutRow("⌥⌘B", "Toggle “Put on Now”")
                        shortcutRow("↩ / Esc", "Create task · Cancel")
                    }

                    shortcutSection(
                        "Search lists (Tasks, Fields, Tools picker)",
                        info: "Requires Arrow keys in search lists above. In the Tools sheet, Return adds or removes the highlighted app."
                    ) {
                        shortcutRow("↑ ↓", "Move highlight while search field is focused")
                        shortcutRow("Return", "Activate highlighted row (select task/field or toggle app in Tools)")
                    }

                    shortcutSection(
                        "Drag and drop",
                        info: "Grab any row by its handle to reorder."
                    ) {
                        shortcutRow("Now", "Drag tasks to reorder the Now list")
                        shortcutRow("Fields", "Drag to reorder fields and tasks in the workbench")
                        shortcutRow("Projects", "Drag to reorder projects (manual sort) and inspector tasks")
                    }
                }
                .turboCard()
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private var taskSelectionStatusLine: String {
        if let t = store.selectedTaskContext {
            return "“\(t.task.title)” · \(t.task.status.title)"
        }
        return "No task selected."
    }

    private func shortcutSection(_ title: String, info: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                if let info {
                    TurboInfoButton(title: title, message: info)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .font(.caption)
            .foregroundStyle(TurboTheme.mutedInk)
        }
    }

    private func shortcutRow(_ keys: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
                .frame(minWidth: 88, alignment: .leading)
            Text(detail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Day Planner Card

private struct DayPlannerCard: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var primarySort: TurboTaskStore.DayPlannerSortKey = .energy
    @State private var secondarySort: TurboTaskStore.DayPlannerSortKey? = .priority
    @State private var primaryDescending = true
    @State private var secondaryDescending = true
    @State private var showPreview = false
    @State private var didApply = false

    private var previewTasks: [TaskContext] {
        store.sortedNowTaskContexts(
            primary: primarySort,
            secondary: secondarySort,
            primaryDescending: primaryDescending,
            secondaryDescending: secondaryDescending
        )
    }

    private var openNowCount: Int {
        store.nowTasks.filter { $0.task.status != .done && !$0.task.isArchived }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TurboTheme.accent)
                Text("Day Planner")
                    .font(.headline)
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Day Planner",
                    message: "Bulk-arrange your Now list. Choose a sort order, preview the result, then apply."
                )
                Spacer()
                Text("\(openNowCount) tasks on Now")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .monospacedDigit()
            }

            // Quick presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick presets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)

                HStack(spacing: 8) {
                    presetButton("Deep Work First") {
                        primarySort = .energy
                        primaryDescending = true
                        secondarySort = .priority
                        secondaryDescending = true
                        showPreview = true
                        didApply = false
                    }
                    presetButton("By Field") {
                        primarySort = .job
                        primaryDescending = false
                        secondarySort = .priority
                        secondaryDescending = true
                        showPreview = true
                        didApply = false
                    }
                    presetButton("Priority Sweep") {
                        primarySort = .priority
                        primaryDescending = true
                        secondarySort = nil
                        secondaryDescending = true
                        showPreview = true
                        didApply = false
                    }
                    presetButton("Active First") {
                        primarySort = .status
                        primaryDescending = false
                        secondarySort = .energy
                        secondaryDescending = true
                        showPreview = true
                        didApply = false
                    }
                }
            }

            Divider()

            // Custom sort controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom sort")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Primary")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                        Picker("Primary", selection: $primarySort) {
                            ForEach(TurboTaskStore.DayPlannerSortKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 120)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Direction")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                        Picker("", selection: $primaryDescending) {
                            Text("↓ High first").tag(true)
                            Text("↑ Low first").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }

                    Rectangle()
                        .fill(TurboTheme.divider)
                        .frame(width: 1, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Secondary")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                        Picker("Secondary", selection: secondarySortBinding) {
                            Text("None").tag("__none__")
                            ForEach(TurboTaskStore.DayPlannerSortKey.allCases) { key in
                                Text(key.title).tag(key.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 120)
                    }

                    if secondarySort != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Direction")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(TurboTheme.mutedInk)
                            Picker("", selection: $secondaryDescending) {
                                Text("↓ High first").tag(true)
                                Text("↑ Low first").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 100)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showPreview.toggle()
                            didApply = false
                        }
                    } label: {
                        Text(showPreview ? "Hide Preview" : "Preview")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        applyOrder()
                    } label: {
                        Text("Apply to Now")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TurboTheme.accent)
                    .disabled(openNowCount == 0)

                    if didApply {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Applied")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .transition(.opacity)
                    }
                }
            }

            // Preview
            if showPreview {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Preview")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TurboTheme.mutedInk)
                            .tracking(0.5)
                        Spacer()
                        Text("\(previewTasks.count) tasks")
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk)
                    }

                    if previewTasks.isEmpty {
                        Text("No open tasks on Now to arrange.")
                            .font(.caption)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(previewTasks.prefix(12).enumerated()), id: \.element.id) { index, ctx in
                                HStack(spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(TurboTheme.mutedInk)
                                        .frame(width: 22, alignment: .trailing)

                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(ctx.jobColor)
                                        .frame(width: 3, height: 18)

                                    Text(ctx.task.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(TurboTheme.ink)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    Text(ctx.task.energy.shortTitle)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(ctx.task.energy.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(ctx.task.energy.accent.opacity(0.14))
                                        )

                                    if !ctx.jobTitle.isEmpty {
                                        Text(ctx.jobTitle)
                                            .font(.caption2)
                                            .foregroundStyle(TurboTheme.mutedInk)
                                            .lineLimit(1)
                                            .frame(maxWidth: 100, alignment: .trailing)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)

                                if index < min(previewTasks.count, 12) - 1 {
                                    Rectangle()
                                        .fill(TurboTheme.divider.opacity(0.3))
                                        .frame(height: 1)
                                        .padding(.leading, 30)
                                }
                            }

                            if previewTasks.count > 12 {
                                Text("… and \(previewTasks.count - 12) more")
                                    .font(.caption2)
                                    .foregroundStyle(TurboTheme.mutedInk)
                                    .padding(.top, 4)
                                    .padding(.leading, 30)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(TurboTheme.nestedCardFill.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(TurboTheme.cardStroke.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .turboCard()
        .onChange(of: primarySort) { _, _ in didApply = false }
        .onChange(of: secondarySort) { _, _ in didApply = false }
        .onChange(of: primaryDescending) { _, _ in didApply = false }
        .onChange(of: secondaryDescending) { _, _ in didApply = false }
    }

    private var secondarySortBinding: Binding<String> {
        Binding(
            get: { secondarySort?.rawValue ?? "__none__" },
            set: { newValue in
                if newValue == "__none__" {
                    secondarySort = nil
                } else {
                    secondarySort = TurboTaskStore.DayPlannerSortKey(rawValue: newValue)
                }
            }
        )
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
    }

    private func applyOrder() {
        let sortedIDs = store.sortedNowTaskIDs(
            primary: primarySort,
            secondary: secondarySort,
            primaryDescending: primaryDescending,
            secondaryDescending: secondaryDescending
        )
        store.applyNowListOrder(sortedTaskIDs: sortedIDs)
        withAnimation(.easeOut(duration: 0.2)) {
            didApply = true
        }
    }
}
