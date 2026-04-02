//
//  AppShellView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var store: TurboTaskStore

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $store.selectedScreen) {
                    ForEach(TurboTaskStore.Screen.primaryCases) { screen in
                        Label(screen.title, systemImage: screen.symbol)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(
                                store.selectedScreen == screen
                                    ? TurboTheme.sidebarSelectionInk
                                    : TurboTheme.sidebarInk
                            )
                            .tag(screen)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                Button {
                    store.selectedScreen = .settings
                } label: {
                    Label(TurboTaskStore.Screen.settings.title, systemImage: TurboTaskStore.Screen.settings.symbol)
                        .font(.body)
                        .foregroundStyle(TurboTheme.sidebarInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(store.selectedScreen == .settings ? TurboTheme.accentSoft : .clear)
                        )
                }
                .buttonStyle(.plain)
                .trainingWheelsTooltip("Settings and full shortcut list · ⌘,")
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 320)
            .background(TurboTheme.sidebar)
        } detail: {
            detailView
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(TurboTheme.background)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("New Job") {
                        store.openComposer(.job)
                    }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .trainingWheelsTooltip("⌘⇧J")
                    Button("New Project") {
                        store.openComposer(.project)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .trainingWheelsTooltip("⌘⇧P")
                    Button("New Task") {
                        store.openComposer(.task)
                    }
                    .keyboardShortcut("t", modifiers: .command)
                    .trainingWheelsTooltip("⌘T")
                    Button("Toggle quick add on Now") {
                        store.performNowShortcut(.focusQuickAdd)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .trainingWheelsTooltip("⌘N")
                    Button("New Task on Now (form)") {
                        store.openComposer(.task, scheduleForNow: true)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .trainingWheelsTooltip("⌘⇧N")
                } label: {
                    Label("New", systemImage: "plus.circle")
                }
                .trainingWheelsTooltip("Create job, project, task, or jump to quick add")

                Button(store.isFocusOverlayVisible ? "Hide Focus Card" : "Show Focus Card") {
                    store.toggleOverlay()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .trainingWheelsTooltip("Floating focus card · ⇧⌘F")
            }
        }
        .sheet(item: $store.composer) { context in
            ItemComposerSheet(context: context)
                .environmentObject(store)
        }
        .tint(TurboTheme.accent)
        .preferredColorScheme(store.preferredColorScheme)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.selectedScreen {
        case .now:
            NowView()
        case .projects:
            ProjectsView()
        case .tasks:
            TasksView()
        case .jobs:
            JobsView()
        case .metrics:
            MetricsView()
        case .settings:
            SettingsView()
        }
    }
}
