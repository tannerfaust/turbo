//
//  TurbotaskApp.swift
//  Turbotask
//
//  Created by Tanner Fause on 01.04.2026.
//

import AppKit
import Combine
import SwiftUI

@main
struct TurbotaskApp: App {
    @StateObject private var store = TurboTaskStore.bootstrap()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        // NSApp / application icon is not safe in App.init — shared app may not exist yet.
        DispatchQueue.main.async {
            Self.applyDockIconFromAssetIfAvailable()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.trainingWheelsEnabled, store.trainingWheelsEnabled)
                .tint(TurboTheme.accent)
                .onAppear {
                    DayBatteryClock.shared.start()
                    ActiveTasksStatusBarController.shared.startObserving(store)
                    _Concurrency.Task { @MainActor in
                        store.releaseTasksReadyToReturnIfNeeded()
                        store.applyIdleTaskAutoArchiveIfNeeded()
                        store.applyDoneTaskAutoArchiveIfNeeded()
                        store.applyArchivedTaskAutoDeleteIfNeeded()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    _Concurrency.Task { @MainActor in
                        store.releaseTasksReadyToReturnIfNeeded()
                        store.applyIdleTaskAutoArchiveIfNeeded()
                        store.applyDoneTaskAutoArchiveIfNeeded()
                        store.applyArchivedTaskAutoDeleteIfNeeded()
                    }
                }
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                    store.releaseTasksReadyToReturnIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flushPersistenceNow()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandMenu("Turbo") {
                Button(store.isFocusOverlayVisible ? "Hide Focus Card" : "Show Focus Card") {
                    store.toggleOverlay()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Toggle quick add on Now…") {
                    store.performNowShortcut(.focusQuickAdd)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Task…") {
                    store.openComposer(.task)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Task on Now (form)…") {
                    store.openComposer(.task, scheduleForNow: true)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Project…") {
                    store.openComposer(.project)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("New Field…") {
                    store.openComposer(.job)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            }

            CommandMenu("Go") {
                Button("Now") {
                    store.selectedScreen = .now
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Projects") {
                    store.selectedScreen = .projects
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Tasks") {
                    store.selectedScreen = .tasks
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Fields") {
                    store.selectedScreen = .jobs
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Metrics") {
                    store.selectedScreen = .metrics
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Battery") {
                    store.selectedScreen = .battery
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Archive") {
                    store.selectedScreen = .archive
                }
                .keyboardShortcut("7", modifiers: .command)

                Divider()

                Button("Settings") {
                    store.selectedScreen = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Now") {
                Button("Toggle Quick Add") {
                    store.performNowShortcut(.focusQuickAdd)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Toggle List / Tree") {
                    store.performNowShortcut(.toggleViewMode)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Grouping Off") {
                    store.performNowShortcut(.setListGrouping(.none))
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button("Group by Fields") {
                    store.performNowShortcut(.setListGrouping(.jobs))
                }
                .keyboardShortcut("j", modifiers: [.command, .option])

                Button("Group by Fields and Projects") {
                    store.performNowShortcut(.setListGrouping(.jobsAndProjects))
                }
                .keyboardShortcut("g", modifiers: [.command, .option])

                Divider()

                Button("Edit Selected Task…") {
                    store.performNowShortcut(.openEditorForSelection)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Start Selected Task") {
                    store.performNowShortcut(.startSelectedTask)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Pause Selected Task") {
                    store.performNowShortcut(.pauseSelectedTask)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Mark Selected Done") {
                    store.performNowShortcut(.markSelectedDone)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Set Selected to Waiting") {
                    store.performNowShortcut(.markSelectedWaiting)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Waiting · ⌘⇧W") {
                    store.performNowShortcut(.markSelectedWaiting)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }

            CommandMenu("Selection") {
                Button("Not Started") {
                    store.applyStatusToSelectedTask(.queued)
                }
                .keyboardShortcut("1", modifiers: [.command, .control])
                Button("In Progress") {
                    store.applyStatusToSelectedTask(.active)
                }
                .keyboardShortcut("2", modifiers: [.command, .control])
                Button("Waiting") {
                    store.applyStatusToSelectedTask(.waiting)
                }
                .keyboardShortcut("3", modifiers: [.command, .control])
                Button("Paused") {
                    store.applyStatusToSelectedTask(.paused)
                }
                .keyboardShortcut("4", modifiers: [.command, .control])
                Button("Done") {
                    store.applyStatusToSelectedTask(.done)
                }
                .keyboardShortcut("5", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    store.appUndoManager.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.appUndoManager.canUndo)

                Button("Redo") {
                    store.appUndoManager.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.appUndoManager.canRedo)
            }

            CommandGroup(after: .undoRedo) {
                Button("Delete Selected Task") {
                    if let ctx = store.selectedTaskContext {
                        store.deleteTask(context: ctx)
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }

    private static func applyDockIconFromAssetIfAvailable() {
        guard let logo = NSImage(named: "AppLogo") else { return }
        NSApplication.shared.applicationIconImage = logo
    }
}
