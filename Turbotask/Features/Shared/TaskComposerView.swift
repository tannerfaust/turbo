//
//  TaskComposerView.swift
//  Turbotask
//
//  Linear-style quick capture for new tasks.
//

import SwiftUI

// MARK: - Shared chrome

struct ComposerChrome<Content: View, FooterLeading: View>: View {
    let breadcrumb: String
    let onClose: () -> Void
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
        .frame(width: 600, height: 500)
        .background(TurboTheme.backgroundRaised)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TurboTheme.ink)

            HStack(spacing: 6) {
                Text(breadcrumb)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

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
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Menu {
            menu()
        } label: {
            pillLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var pillLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? TurboTheme.ink : TurboTheme.mutedInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? TurboTheme.accentSoft.opacity(0.55) : TurboTheme.nestedCardFill.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TurboTheme.cardStroke.opacity(isActive ? 0.95 : 0.55), lineWidth: 1)
        )
    }
}

struct ComposerTogglePill: View {
    let icon: String
    let title: String
    var isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isOn ? TurboTheme.ink : TurboTheme.mutedInk)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? TurboTheme.ink : TurboTheme.mutedInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? TurboTheme.accentSoft.opacity(0.65) : TurboTheme.nestedCardFill.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TurboTheme.cardStroke.opacity(isOn ? 0.95 : 0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Task composer

struct TaskComposerView: View {
    @EnvironmentObject private var store: TurboTaskStore

    let preferredJobID: UUID?
    let preferredProjectID: UUID?
    let preferredStatus: TaskStatus?
    let scheduleForNow: Bool

    @AppStorage("composer_create_more") private var createMore = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    @State private var selectedJobID: UUID?
    @State private var selectedProjectID: UUID?
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

    init(
        preferredJobID: UUID?,
        preferredProjectID: UUID?,
        preferredStatus: TaskStatus? = nil,
        scheduleForNow: Bool
    ) {
        self.preferredJobID = preferredJobID
        self.preferredProjectID = preferredProjectID
        self.preferredStatus = preferredStatus
        self.scheduleForNow = scheduleForNow
        _selectedJobID = State(initialValue: preferredJobID)
        _selectedProjectID = State(initialValue: preferredProjectID)
        _status = State(initialValue: preferredStatus ?? .queued)
        _isScheduledNow = State(initialValue: scheduleForNow)
    }

    var body: some View {
        ComposerChrome(
            breadcrumb: breadcrumb,
            onClose: { store.clearComposer() },
            content: { composerBody },
            footerLeading: { toolsFooterButton },
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
    }

    private var composerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleField
                notesField
                capturePills
                advancedPanels
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var titleField: some View {
        TextField("Task title", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(TurboTheme.ink)
            .focused($titleFocused)
            .padding(.bottom, 10)
    }

    private var notesField: some View {
        TextField("Add notes…", text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(TurboTheme.ink)
            .lineLimit(2...6)
            .focused($notesFocused)
            .padding(.bottom, 16)
    }

    private var capturePills: some View {
        FlowLayout(spacing: 8) {
            statusPill
            energyPill
            fieldPill
            if selectedJobID != nil {
                projectPill
            }
            cadencePill
            ComposerTogglePill(
                icon: isScheduledNow ? "pin.fill" : "pin",
                title: isScheduledNow ? "On Now" : "Now",
                isOn: isScheduledNow,
                action: { isScheduledNow.toggle() }
            )
            toolsPill
            planPill
            morePill
        }
    }

    private var statusPill: some View {
        ComposerCapturePill(
            icon: "circle.fill",
            iconColor: status.accent,
            title: status.title,
            isActive: status != .queued
        ) {
            ForEach(TaskStatus.allCases) { option in
                Button {
                    status = option
                } label: {
                    Label {
                        Text(option.title)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(option.accent)
                    }
                    if status == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private var energyPill: some View {
        ComposerCapturePill(
            icon: "bolt.fill",
            iconColor: energy.accent,
            title: energy.shortTitle,
            isActive: energy != .deepFocus
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
            icon: "briefcase",
            title: fieldLabel,
            isActive: selectedJobID != nil
        ) {
            Button {
                selectedJobID = nil
                selectedProjectID = nil
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
                        syncProjectSelection()
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
            icon: "square.stack.3d.up",
            title: projectLabel,
            isActive: selectedProjectID != nil
        ) {
            Button {
                selectedProjectID = nil
            } label: {
                HStack {
                    Text("No project")
                    if selectedProjectID == nil { Image(systemName: "checkmark") }
                }
            }
            if !availableProjects.isEmpty {
                Divider()
                ForEach(availableProjects) { context in
                    Button {
                        selectedProjectID = context.project.id
                    } label: {
                        HStack {
                            Text(context.project.displayTitle)
                            if selectedProjectID == context.project.id { Image(systemName: "checkmark") }
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
            isActive: cadence != .oneOff
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
            title: toolsLabel,
            isActive: !toolBundleIDs.isEmpty
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

    private var planPill: some View {
        ComposerCapturePill(
            icon: "calendar",
            title: planLabel,
            isActive: hasStartDate || hasEndDate
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
        ComposerCapturePill(icon: "ellipsis", title: "More") {
            if cadence == .repeatable {
                Stepper("Reappear: \(repeatEveryMinutes) min", value: $repeatEveryMinutes, in: 15...2880, step: 15)
            }
            if cadence == .kpi {
                Stepper("Amount: \(kpiTarget)", value: $kpiTarget, in: 1...500)
                Toggle("Use rounds", isOn: $hasKpiRounds)
                if hasKpiRounds {
                    Stepper("Rounds: \(kpiRoundsRemaining)", value: $kpiRoundsRemaining, in: 1...50)
                }
                Toggle("Reappear timer", isOn: $hasRepeatDelay)
                if hasRepeatDelay {
                    Stepper("After: \(repeatEveryMinutes) min", value: $repeatEveryMinutes, in: 15...2880, step: 15)
                }
            }
            if cadence == .oneOff {
                Text("Select Repeatable or KPI in Pattern for more options.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private var advancedPanels: some View {
        if cadence != .oneOff {
            VStack(alignment: .leading, spacing: 10) {
                if cadence == .repeatable {
                    cadenceDetailRow(
                        icon: "repeat",
                        title: "Reappears every \(repeatEveryMinutes) minutes after completion"
                    )
                }
                if cadence == .kpi {
                    cadenceDetailRow(
                        icon: "number",
                        title: "Count to \(kpiTarget)\(hasKpiRounds ? " · \(kpiRoundsRemaining) round(s) left" : "")"
                    )
                }
            }
            .padding(.top, 14)
        }
    }

    private func cadenceDetailRow(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)
            Text(title)
                .font(.caption)
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.6))
        )
    }

    private var toolsFooterButton: some View {
        Button {
            toolsPickerOpen = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Attach tools (Mac apps)")
    }

    private var keyboardTraps: some View {
        VStack(spacing: 0) {
            Button("") { status = .queued }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("") { status = .active }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("") { status = .waiting }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("") { status = .paused }
                .keyboardShortcut("4", modifiers: [.command, .option])
            Button("") { status = .done }
                .keyboardShortcut("5", modifiers: [.command, .option])
            Button("") { isScheduledNow.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var breadcrumb: String {
        var parts: [String] = []
        if let selectedJobID, let job = store.jobs.first(where: { $0.id == selectedJobID }) {
            parts.append(job.title)
            if let selectedProjectID,
               let project = availableProjects.first(where: { $0.project.id == selectedProjectID }) {
                parts.append(project.project.displayTitle)
            }
        } else {
            parts.append("Inbox")
        }
        parts.append("New task")
        return parts.joined(separator: " › ")
    }

    private var fieldLabel: String {
        guard let selectedJobID,
              let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
            return "Inbox"
        }
        return job.title
    }

    private var projectLabel: String {
        guard let selectedProjectID,
              let project = availableProjects.first(where: { $0.project.id == selectedProjectID }) else {
            return "Project"
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

    private func syncProjectSelection() {
        if selectedJobID == nil {
            selectedProjectID = nil
            return
        }
        if let pid = selectedProjectID,
           !availableProjects.contains(where: { $0.project.id == pid }) {
            selectedProjectID = nil
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
            startDate: hasStartDate ? cal.startOfDay(for: startDate) : nil,
            endDate: hasEndDate ? cal.startOfDay(for: endDate) : nil
        )

        if createMore {
            title = ""
            notes = ""
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
        let width = proposal.width ?? 0
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
