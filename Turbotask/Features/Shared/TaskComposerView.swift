//
//  TaskComposerView.swift
//  Turbotask
//
//  Linear-style quick capture for new tasks.
//

import SwiftUI

// MARK: - Shared chrome

struct ComposerChrome<Content: View, FooterLeading: View>: View {
    var breadcrumb: String? = nil
    var headerLeading: AnyView? = nil
    let onClose: () -> Void
    var size = CGSize(width: 600, height: 500)
    var headerAccessory: AnyView? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerLeading: () -> FooterLeading
    let createMore: Binding<Bool>
    let createTitle: String
    let canCreate: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.65)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().opacity(0.65)
            footer
        }
        .frame(width: size.width, height: size.height)
        .background(TurboTheme.backgroundRaised)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let headerLeading {
                headerLeading
            } else if let breadcrumb {
                Text(breadcrumb)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let headerAccessory {
                headerAccessory
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(TurboTheme.nestedCardFill)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close · Esc")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerLeading()

            Spacer(minLength: 0)

            Toggle(isOn: createMore) {
                Text("Create more")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button(createTitle, action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Capture pill

struct ComposerCapturePill<MenuContent: View>: View {
    let icon: String
    var iconColor: Color = TurboTheme.mutedInk
    let title: String
    var isActive: Bool = false
    var helpText: String = ""
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Menu {
            menu()
        } label: {
            pillLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(TurboTheme.nestedCardFill)
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1))
        .help(helpText.isEmpty ? title : helpText)
    }

    private var pillLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: icon == "circle.fill" || icon == "circle" ? 9 : 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? TurboTheme.ink : TurboTheme.mutedInk)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TurboTheme.mutedInk.opacity(0.75))
        }
        .contentShape(Capsule())
    }
}

struct ComposerTogglePill: View {
    let icon: String
    let title: String
    var isOn: Bool
    var helpText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? TurboTheme.ink : TurboTheme.mutedInk)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? TurboTheme.ink : TurboTheme.mutedInk)
                    .lineLimit(1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(TurboTheme.nestedCardFill)
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1))
        .help(helpText.isEmpty ? title : helpText)
    }
}

// MARK: - Now button (icon-only glow circle)

struct ComposerNowButton: View {
    @Binding var isOn: Bool
    var glowColor: Color

    @State private var bounceScale: CGFloat = 1.0

    var body: some View {
        Button {
            isOn.toggle()
            // Brief bounce on press
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bounceScale = 1.18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    bounceScale = 1.0
                }
            }
        } label: {
            ZStack {
                // Main circle — solid fill when on, subtle when off
                Circle()
                    .fill(isOn ? glowColor.opacity(0.18) : TurboTheme.nestedCardFill)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(
                                isOn ? glowColor.opacity(0.55) : TurboTheme.cardStroke.opacity(0.85),
                                lineWidth: 1
                            )
                    )

                // Lightning bolt icon
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOn ? glowColor : TurboTheme.mutedInk.opacity(0.45))
            }
            .frame(width: 28, height: 28)
            .scaleEffect(bounceScale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isOn ? "Remove from Now · ⌥⌘B" : "Show in Now · ⌥⌘B")
        .accessibilityLabel(isOn ? "Now active" : "Schedule for now")
    }
}

// MARK: - Status menu (icon-only, title row)

struct ComposerStatusMenuButton: View {
    @Binding var selection: TaskStatus
    var accentColor: Color

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(TurboTheme.nestedCardFill)
                    .overlay(
                        Circle()
                            .stroke(TurboTheme.cardStroke.opacity(0.7), lineWidth: 1)
                    )
                TaskStatusRowIndicator(status: selection, jobColor: accentColor, diameter: 20)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Status: \(selection.title) · click to change · ⌥⌘1–5")
        .accessibilityLabel("Task status: \(selection.title)")
        .accessibilityHint("Opens status menu")
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TaskStatus.allCases) { option in
                    Button {
                        selection = option
                        showPicker = false
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(option.accent)
                                .frame(width: 8, height: 8)
                            Text(option.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TurboTheme.ink)
                            Spacer(minLength: 20)
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(TurboTheme.mutedInk)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option ? TurboTheme.nestedCardFill : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 180)
        }
    }
}

// MARK: - Task composer

struct TaskComposerView: View {
    @EnvironmentObject private var store: TurboTaskStore

    let preferredJobID: UUID?
    let preferredProjectID: UUID?
    let preferredOperationID: UUID?
    let preferredStatus: TaskStatus?
    let scheduleForNow: Bool

    @AppStorage("composer_create_more") private var createMore = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    @State private var selectedJobID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var selectedOperationID: UUID?
    @State private var title = ""
    @State private var notes = ""
    @State private var status: TaskStatus = .queued
    @State private var energy: TaskEnergy = .deepFocus
    @State private var cadence: TaskCadence = .oneOff
    @State private var isScheduledNow: Bool
    @State private var repeatEveryMinutes = 60
    @State private var kpiTarget = 10
    @State private var hasKpiRounds = false
    @State private var kpiRoundsRemaining = 1
    @State private var hasRepeatDelay = false
    @State private var toolBundleIDs: [String] = []
    @State private var toolsPickerOpen = false
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var subtasks: [TaskSubtask] = []

    init(
        preferredJobID: UUID?,
        preferredProjectID: UUID?,
        preferredOperationID: UUID? = nil,
        preferredStatus: TaskStatus? = nil,
        scheduleForNow: Bool
    ) {
        self.preferredJobID = preferredJobID
        self.preferredProjectID = preferredProjectID
        self.preferredOperationID = preferredOperationID
        self.preferredStatus = preferredStatus
        self.scheduleForNow = scheduleForNow
        _selectedJobID = State(initialValue: preferredJobID)
        _selectedProjectID = State(initialValue: preferredProjectID)
        _selectedOperationID = State(initialValue: preferredOperationID)
        _status = State(initialValue: preferredStatus ?? .queued)
        _isScheduledNow = State(initialValue: scheduleForNow)
    }

    var body: some View {
        ComposerChrome(
            headerLeading: AnyView(locationHeaderPills),
            onClose: { store.clearComposer() },
            size: composerSize,
            headerAccessory: AnyView(nowHeaderButton),
            content: { composerBody },
            footerLeading: { EmptyView() },
            createMore: $createMore,
            createTitle: "Create task",
            canCreate: canCreate,
            onCreate: createTask
        )
        .overlay { keyboardTraps }
        .onAppear {
            syncProjectSelection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                titleFocused = true
            }
        }
        .onChange(of: selectedJobID) {
            syncProjectSelection()
        }
        .sheet(isPresented: $toolsPickerOpen) {
            TaskToolsPickerSheet(bundleIDs: $toolBundleIDs)
                .environmentObject(store)
        }
        .animation(.easeInOut(duration: 0.18), value: cadence)
    }

    private var composerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleField
            notesField
            advancedPanels
            capturePills
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var titleField: some View {
        HStack(alignment: .center, spacing: 10) {
            ComposerStatusMenuButton(selection: $status, accentColor: destinationAccent)

            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(TurboTheme.ink)
                .focused($titleFocused)
        }
    }

    private var notesField: some View {
        TextField("Add description or notes...", text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(TurboTheme.ink)
            .focused($notesFocused)
            .lineLimit(3...)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
    }

    private var capturePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                energyPill
                cadencePill
                toolsPill
                subtasksPill
                planPill
                morePill
            }
        }
    }

    private var locationHeaderPills: some View {
        HStack(spacing: 6) {
            fieldPill
            if selectedJobID != nil {
                projectPill
            }
        }
    }

    private var nowHeaderButton: some View {
        ComposerNowButton(isOn: $isScheduledNow, glowColor: destinationAccent)
    }

    private var destinationAccent: Color {
        if let selectedJobID,
           let job = store.jobs.first(where: { $0.id == selectedJobID }) {
            return job.palette.color
        }
        return TurboTheme.inboxAccent
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
                        if energy == option {
                            Image(systemName: "checkmark")
                        }
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
                    Menu {
                        Button {
                            selectedJobID = job.id
                            selectedProjectID = nil
                            selectedOperationID = nil
                        } label: {
                            HStack {
                                Text("Field only")
                                if selectedJobID == job.id && selectedProjectID == nil && selectedOperationID == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        let projects = store.projectContexts.filter { $0.jobID == job.id }
                        if !projects.isEmpty {
                            Divider()
                            Text("Projects")
                            ForEach(projects) { context in
                                Button {
                                    selectedJobID = job.id
                                    selectedProjectID = context.project.id
                                    selectedOperationID = nil
                                } label: {
                                    HStack {
                                        Text(context.project.displayTitle)
                                        if selectedProjectID == context.project.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }

                        let operations = store.operationContexts(jobID: job.id).filter { !$0.operation.isArchived }
                        if !operations.isEmpty {
                            Divider()
                            Text("Operations")
                            ForEach(operations) { context in
                                Button {
                                    selectedJobID = job.id
                                    selectedOperationID = context.operation.id
                                    selectedProjectID = nil
                                } label: {
                                    HStack {
                                        Text(context.operation.title)
                                        if selectedOperationID == context.operation.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(job.title, systemImage: "briefcase")
                    }
                }
            }
        }
    }

    private var projectPill: some View {
        ComposerCapturePill(
            icon: selectedOperationID != nil ? "arrow.triangle.2.circlepath" : "square.stack.3d.up",
            title: projectLabel,
            isActive: selectedProjectID != nil || selectedOperationID != nil,
            helpText: "Placement: \(projectLabel)"
        ) {
            Button {
                selectedProjectID = nil
                selectedOperationID = nil
            } label: {
                HStack {
                    Text(selectedOperationID != nil ? "No operation" : "No project")
                    if selectedProjectID == nil && selectedOperationID == nil { Image(systemName: "checkmark") }
                }
            }
            if !availableProjects.isEmpty {
                Divider()
                Text("Projects")
                ForEach(availableProjects) { context in
                    Button {
                        selectedProjectID = context.project.id
                        selectedOperationID = nil
                    } label: {
                        HStack {
                            Text(context.project.displayTitle)
                            if selectedProjectID == context.project.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            if !availableOperations.isEmpty {
                Divider()
                Text("Operations")
                ForEach(availableOperations) { context in
                    Button {
                        selectedOperationID = context.operation.id
                        selectedProjectID = nil
                    } label: {
                        HStack {
                            Text(context.operation.title)
                            if selectedOperationID == context.operation.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }

    // Now button is in the header, not here as a pill anymore

    private var cadencePill: some View {
        ComposerCapturePill(
            icon: cadenceIcon,
            title: cadence.title,
            isActive: cadence != .oneOff,
            helpText: "Pattern: \(cadence.title)"
        ) {
            ForEach(TaskCadence.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cadence = option
                    }
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
            title: toolsLabel,
            isActive: !toolBundleIDs.isEmpty,
            helpText: toolBundleIDs.isEmpty
                ? "Choose Mac apps needed for this task"
                : "\(toolBundleIDs.count) tool\(toolBundleIDs.count == 1 ? "" : "s") attached"
        ) {
            Button("Choose apps…") {
                toolsPickerOpen = true
            }
            if !toolBundleIDs.isEmpty {
                Button("Clear tools", role: .destructive) {
                    toolBundleIDs = []
                }
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
            helpText: "Set optional start and target dates"
        ) {
            Toggle("Start date", isOn: $hasStartDate)
            if hasStartDate {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
            }
            Toggle("Target end", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Ends", selection: $endDate, displayedComponents: .date)
            }
        }
    }

    private var morePill: some View {
        ComposerCapturePill(
            icon: "ellipsis",
            title: "More",
            helpText: "Additional task options"
        ) {
            if cadence == .repeatable {
                Stepper("Reappear: \(durationLabel(repeatEveryMinutes))", value: $repeatEveryMinutes, in: 15...2880, step: 15)
            }
            if cadence == .kpi {
                Stepper("Amount: \(kpiTarget)", value: $kpiTarget, in: 1...500)
                Toggle("Use rounds", isOn: $hasKpiRounds)
                if hasKpiRounds {
                    Stepper("Rounds: \(kpiRoundsRemaining)", value: $kpiRoundsRemaining, in: 1...50)
                }
                Toggle("Reappear timer", isOn: $hasRepeatDelay)
                if hasRepeatDelay {
                    Stepper("After: \(durationLabel(repeatEveryMinutes))", value: $repeatEveryMinutes, in: 15...2880, step: 15)
                }
            }
            if cadence == .oneOff {
                Button("Show in Now") {
                    isScheduledNow = true
                }
                .disabled(isScheduledNow)
            }
        }
    }

    @ViewBuilder
    private var advancedPanels: some View {
        switch cadence {
        case .oneOff:
            EmptyView()
        case .repeatable:
            patternSettingsCard(title: "Repeat settings", icon: "repeat") {
                settingStepper(
                    title: "Reappear after completion",
                    valueText: durationLabel(repeatEveryMinutes),
                    value: $repeatEveryMinutes,
                    range: 15...2880,
                    step: 15,
                    help: "How long after completion the task becomes available again"
                )
            }
        case .kpi:
            patternSettingsCard(title: "KPI settings", icon: "number") {
                settingStepper(
                    title: "Target amount",
                    valueText: "\(kpiTarget)",
                    value: $kpiTarget,
                    range: 1...500,
                    help: "The count required to complete this KPI"
                )

                settingsDivider

                settingToggle(title: "Use rounds", isOn: $hasKpiRounds)
                    .help("Track the KPI across a fixed number of rounds")
                if hasKpiRounds {
                    settingStepper(
                        title: "Rounds",
                        valueText: "\(kpiRoundsRemaining)",
                        value: $kpiRoundsRemaining,
                        range: 1...50,
                        step: 1,
                        help: "Number of KPI rounds remaining"
                    )
                }

                settingsDivider

                settingToggle(title: "Reappear timer", isOn: $hasRepeatDelay)
                    .help("Wait before making the KPI available for another count")
                if hasRepeatDelay {
                    settingStepper(
                        title: "Reappear after",
                        valueText: durationLabel(repeatEveryMinutes),
                        value: $repeatEveryMinutes,
                        range: 15...2880,
                        step: 15,
                        help: "Delay before the next KPI count becomes available"
                    )
                }
            }
        }
    }

    private func patternSettingsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TurboTheme.ink)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TurboTheme.cardStroke.opacity(0.42), lineWidth: 1)
        )
        .padding(.bottom, 12)
    }

    private func settingStepper(
        title: String,
        valueText: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        help: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(TurboTheme.mutedInk)
            Spacer(minLength: 12)
            Text(valueText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TurboTheme.ink)
                .monospacedDigit()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
        .help(help)
    }

    private func settingToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var settingsDivider: some View {
        Divider().opacity(0.55)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60) hr" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    private var composerSize: CGSize {
        switch cadence {
        case .oneOff:
            CGSize(width: 720, height: 380)
        case .repeatable:
            CGSize(width: 720, height: 450)
        case .kpi:
            CGSize(width: 720, height: 550)
        }
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
              let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
            return "Inbox"
        }
        return job.title
    }

    private var projectLabel: String {
        if let selectedOperationID,
           let operation = availableOperations.first(where: { $0.operation.id == selectedOperationID }) {
            return operation.operation.title
        }
        guard let selectedProjectID,
              let project = availableProjects.first(where: { $0.project.id == selectedProjectID }) else {
            return "Project / Operation"
        }
        return project.project.displayTitle
    }

    private var toolsLabel: String {
        toolBundleIDs.isEmpty ? "Tools" : "\(toolBundleIDs.count) tool\(toolBundleIDs.count == 1 ? "" : "s")"
    }

    private var planLabel: String {
        if hasStartDate && hasEndDate { return "Plan dates" }
        if hasStartDate { return "Start date" }
        if hasEndDate { return "End date" }
        return "Plan"
    }

    private var cadenceIcon: String {
        switch cadence {
        case .oneOff: "1.circle"
        case .repeatable: "repeat"
        case .kpi: "number"
        }
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableProjects: [ProjectContext] {
        guard let selectedJobID else { return [] }
        return store.projectContexts.filter { $0.jobID == selectedJobID }
    }

    private var availableOperations: [OperationContext] {
        guard let selectedJobID else { return [] }
        return store.operationContexts(jobID: selectedJobID).filter { !$0.operation.isArchived }
    }

    private func syncProjectSelection() {
        if selectedJobID == nil {
            selectedProjectID = nil
            selectedOperationID = nil
            return
        }
        if let pid = selectedProjectID,
           !availableProjects.contains(where: { $0.project.id == pid }) {
            selectedProjectID = nil
        }
        if let oid = selectedOperationID,
           !availableOperations.contains(where: { $0.operation.id == oid }) {
            selectedOperationID = nil
        }
    }

    private func createTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let cal = Calendar.current
        store.addTask(
            title: trimmedTitle,
            summary: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            energy: energy,
            cadence: cadence,
            isScheduledNow: isScheduledNow,
            repeatEveryMinutes: cadence == .repeatable || (cadence == .kpi && hasRepeatDelay) ? repeatEveryMinutes : nil,
            kpiTarget: cadence == .kpi ? kpiTarget : nil,
            kpiRoundsRemaining: cadence == .kpi && hasKpiRounds ? kpiRoundsRemaining : nil,
            toolBundleIDs: toolBundleIDs,
            jobID: selectedJobID,
            projectID: selectedProjectID,
            operationID: selectedOperationID,
            startDate: hasStartDate ? cal.startOfDay(for: startDate) : nil,
            endDate: hasEndDate ? cal.startOfDay(for: endDate) : nil,
            subtasks: Task.normalizedSubtasks(subtasks)
        )

        if createMore {
            title = ""
            notes = ""
            subtasks = []
            titleFocused = true
        } else {
            store.clearComposer()
        }
    }
}

// MARK: - Flow layout for pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width + spacing
        }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Task composer pills") {
    TaskComposerView(
        preferredJobID: nil,
        preferredProjectID: nil,
        scheduleForNow: false
    )
    .environmentObject(TurboTaskStore.preview)
    .frame(width: 720, height: 380)
}
#endif
