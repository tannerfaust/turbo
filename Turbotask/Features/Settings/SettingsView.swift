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
                            set: { store.setThemeMode($0) }
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
                    Text("Workspace")
                        .font(.headline)
                        .foregroundStyle(TurboTheme.ink)

                    Stepper(
                        "Daily capacity: \(store.dailyCapacityMinutes) min",
                        value: Binding(
                            get: { store.dailyCapacityMinutes },
                            set: { store.setDailyCapacityMinutes($0) }
                        ),
                        in: 120...960,
                        step: 15
                    )

                    Toggle(
                        "Show floating focus card",
                        isOn: Binding(
                            get: { store.isFocusOverlayVisible },
                            set: { isVisible in
                                if isVisible != store.isFocusOverlayVisible {
                                    store.toggleOverlay()
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                }
                .turboCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard & learning")
                        .font(.headline)
                        .foregroundStyle(TurboTheme.ink)

                    Toggle(
                        "Show keyboard hints (training wheels)",
                        isOn: $store.trainingWheelsEnabled
                    )
                    .toggleStyle(.switch)

                    Text("Shows inline hint lines where they exist, plus hover tooltips on buttons and controls (macOS help tags).")
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)

                    Toggle(
                        "Arrow keys in search lists",
                        isOn: $store.typeaheadListNavigationEnabled
                    )
                    .toggleStyle(.switch)

                    Text("While a search field is focused, ↑ ↓ move the highlight and Return selects (Tasks, Jobs, Projects, app picker).")
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)

                    Divider()
                        .padding(.vertical, 4)

                    Text("Selected task")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TurboTheme.ink)

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

                    Text("Same as the Now / Selection menus: ⌘↩ start · ⌘P pause · ⌘D done · ⌘⇧U or ⌘⇧W waiting · ⌃⌘1…5 sets status. Select a task first.")
                        .font(.caption2)
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                .turboCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Shortcut map")
                        .font(.headline)
                        .foregroundStyle(TurboTheme.ink)

                    Text("Same shortcuts appear in the menu bar (Turbo, Go, Now). Turn on “training wheels” to see hover hints on buttons.")
                        .font(.caption)
                        .foregroundStyle(TurboTheme.mutedInk)

                    shortcutSection("Navigation") {
                        shortcutRow("⌘1", "Now")
                        shortcutRow("⌘2", "Projects")
                        shortcutRow("⌘3", "Tasks")
                        shortcutRow("⌘4", "Jobs")
                        shortcutRow("⌘5", "Metrics")
                        shortcutRow("⌘,", "Settings")
                    }

                    shortcutSection("Create & capture") {
                        shortcutRow("⌘T", "New task (composer). If quick add is open on Now, toggles “Now” instead.")
                        shortcutRow("⌘⇧N", "New task on Now (full composer)")
                        shortcutRow("⌘⇧P", "New project")
                        shortcutRow("⌘⇧J", "New job")
                        shortcutRow("⌘N", "Toggle quick add on Now")
                        shortcutRow("⇧⌘A", "Toggle quick add on Now (same as ⌘N)")
                    }

                    shortcutSection("Focus & layout") {
                        shortcutRow("⇧⌘F", "Show or hide floating focus card")
                        shortcutRow("⇧⌘L", "Now: toggle list vs tree")
                        shortcutRow("⌘E", "Edit selected task (sheet)")
                    }

                    shortcutSection("Start, pause, finish (selected task)") {
                        Text("Select a task on Now, Tasks, Projects, or Jobs. Then:")
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .padding(.bottom, 2)
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

                    shortcutSection("Search lists (Tasks, Jobs, Tools picker)") {
                        shortcutRow("↑ ↓", "Move highlight while search field is focused")
                        shortcutRow("Return", "Activate highlighted row (select task/job or toggle app in Tools)")
                        Text("Requires “Arrow keys in search lists” above. Tools sheet: add/remove the highlighted app.")
                            .font(.caption2)
                            .foregroundStyle(TurboTheme.mutedInk)
                    }

                    shortcutSection("Quick add on Now") {
                        shortcutRow("Esc", "Close quick add")
                        shortcutRow("Return", "Create task (when title field is filled)")
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

    private func shortcutSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
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
