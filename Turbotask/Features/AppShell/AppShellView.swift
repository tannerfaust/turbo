//
//  AppShellView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var store: TurboTaskStore
    @State private var sidebarSelection: TurboTaskStore.Screen?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $sidebarSelection) {
                    ForEach(TurboTaskStore.Screen.primaryCases) { screen in
                        Label(screen.title, systemImage: screen.symbol)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(
                                currentScreen == screen
                                    ? TurboTheme.sidebarSelectionInk
                                    : TurboTheme.sidebarInk
                            )
                            .tag(screen)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                VStack(spacing: 6) {
                    footerScreenButton(.battery, tooltip: "Day battery · ⌘6")
                    footerScreenButton(.archive, tooltip: "Archived tasks · ⌘7")
                    footerScreenButton(.settings, tooltip: "Settings and full shortcut list · ⌘,")
                }
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

                Button {
                    store.toggleOverlay()
                } label: {
                    Label(
                        store.isFocusOverlayVisible ? "Hide focus card" : "Show focus card",
                        systemImage: store.isFocusOverlayVisible
                            ? "rectangle.on.rectangle"
                            : "rectangle.dashed"
                    )
                }
                .labelStyle(.iconOnly)
                .help(store.isFocusOverlayVisible ? "Hide focus card · ⇧⌘F" : "Show focus card · ⇧⌘F")
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .trainingWheelsTooltip("Floating focus card · ⇧⌘F")
            }
        }
        .sheet(item: Binding(
            get: { store.composer },
            set: { val in DispatchQueue.main.async { store.composer = val } }
        )) { context in
            ItemComposerSheet(context: context)
                .environmentObject(store)
        }
        .sheet(item: Binding(
            get: { store.multitaskUpgradeOffer },
            set: { val in DispatchQueue.main.async { store.multitaskUpgradeOffer = val } }
        ), onDismiss: {
            DispatchQueue.main.async { store.cancelMultitaskUpgradeOffer() }
        }) { offer in
            MultitaskUpgradeSheet(offer: offer)
                .environmentObject(store)
        }
        .alert(
            "Too many in progress",
            isPresented: Binding(
                get: { store.parallelActiveLimitMessage != nil },
                set: { val in DispatchQueue.main.async { if !val { store.clearParallelActiveLimitMessage() } } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.clearParallelActiveLimitMessage()
            }
        } message: {
            Text(store.parallelActiveLimitMessage ?? "")
        }
        .tint(TurboTheme.accent)
        .preferredColorScheme(store.preferredColorScheme)
        .onAppear {
            syncSidebarSelection()
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard let newValue, newValue != store.selectedScreen else { return }
            DispatchQueue.main.async {
                store.selectedScreen = newValue
            }
        }
        .onChange(of: store.selectedScreen) { _, _ in
            syncSidebarSelection()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 0) {
            ScreenShortcutBar(screen: currentScreen)

            Group {
                switch currentScreen {
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
                case .battery:
                    DayBatteryView()
                case .archive:
                    ArchiveView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func footerScreenButton(_ screen: TurboTaskStore.Screen, tooltip: String) -> some View {
        Button {
            sidebarSelection = screen
            DispatchQueue.main.async {
                store.selectedScreen = screen
            }
        } label: {
            Label(screen.title, systemImage: screen.symbol)
                .font(.body)
                .foregroundStyle(TurboTheme.sidebarInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(currentScreen == screen ? TurboTheme.accentSoft : .clear)
                )
        }
        .buttonStyle(.plain)
        .trainingWheelsTooltip(tooltip)
    }

    private var currentScreen: TurboTaskStore.Screen {
        sidebarSelection ?? store.selectedScreen
    }

    private func syncSidebarSelection() {
        guard sidebarSelection != store.selectedScreen else { return }
        sidebarSelection = store.selectedScreen
    }
}
