//
//  AILimitControlBar.swift
//  Turbotask
//
//  The AI-limit surface for Now. Each assistant (Claude, Codex, Cursor,
//  Antigravity) has its own usage cap that resets on its own clock, so the
//  control tracks and pauses each one independently. When you hit a cap, flip
//  that one assistant's switch — Turbo pauses just its tasks and counts down,
//  live, to that assistant's next reset.
//

import SwiftUI

// MARK: - Agent icon (stripped monochrome glyph, brand-tinted)

struct AIAgentIcon: View {
    let provider: AIDependencyProvider
    var size: CGFloat = 18
    var tint: Color? = nil

    /// Monochrome brand glyph shipped in the asset catalog (template-rendered).
    private var assetName: String {
        switch provider {
        case .claude: "ai-claude"
        case .codex: "ai-codex"
        case .cursor: "ai-cursor"
        case .antigravity: "ai-antigravity"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(tint ?? provider.accent)
    }
}

// MARK: - Provider badge (compact, for task rows)

struct AIDependencyBadge: View {
    let provider: AIDependencyProvider
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: provider.symbol)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            if !compact {
                Text(provider.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(provider.accent)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Capsule()
                .fill(provider.accent.opacity(0.14))
                .overlay(Capsule().stroke(provider.accent.opacity(0.28), lineWidth: 0.5))
        )
        .accessibilityLabel("AI task · \(provider.title)")
    }
}

// MARK: - Shared helpers

private enum AICountdown {
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    static func remainingFraction(holdUntil: Date, schedule: AILimitSchedule, now: Date) -> Double {
        let remaining = holdUntil.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        let window = schedule.nextReset(after: holdUntil).timeIntervalSince(holdUntil)
        guard window > 0 else { return 0 }
        return min(1, max(0, remaining / window))
    }
}

private func scheduleSummary(_ schedule: AILimitSchedule) -> String {
    let days = schedule.weekdaySummary()
    let dayText = days == "Every day" ? "daily" : days
    return "resets \(schedule.resetTimeLabel()) · \(dayText)"
}

// MARK: - Toolbar control

struct AILimitControlBar: View {
    @EnvironmentObject private var store: TurboTaskStore

    @State private var isPopoverOpen = false

    var body: some View {
        Button {
            isPopoverOpen.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens per-assistant AI limit schedules and controls")
        .popover(isPresented: $isPopoverOpen, arrowEdge: .bottom) {
            AILimitPanel(isPresented: $isPopoverOpen)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let soonest = soonestActive {
            let tint = soonest.provider.accent
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 7) {
                    AIDepletionRing(
                        fraction: AICountdown.remainingFraction(
                            holdUntil: soonest.until,
                            schedule: store.aiLimitSchedule(for: soonest.provider),
                            now: context.date
                        ),
                        tint: tint
                    )
                    Text(AICountdown.compact(soonest.until.timeIntervalSince(context.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tint)
                    if store.activeAILimitProviders.count > 1 {
                        Text("·\(store.activeAILimitProviders.count)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(tint.opacity(0.7))
                    }
                }
                .glassControlChrome(active: true, tint: tint)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                Text("AI limit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
            }
            .glassControlChrome()
        }
    }

    private var soonestActive: (provider: AIDependencyProvider, until: Date)? {
        store.activeAILimitProviders
            .compactMap { provider in store.aiLimitHoldUntil(for: provider).map { (provider, $0) } }
            .min { $0.1 < $1.1 }
    }

    private var helpText: String {
        if let soonest = soonestActive {
            return "\(soonest.provider.title) paused · back \(soonest.until.formatted(date: .omitted, time: .shortened))"
        }
        let n = store.aiDependentOpenTaskCount
        if n == 0 { return "AI limits · no tasks waiting on an assistant yet" }
        return "AI limits · \(n) task\(n == 1 ? "" : "s") depend on an assistant"
    }

    private var accessibilityLabel: String {
        soonestActive != nil ? "AI limit active" : "AI limits"
    }
}

// MARK: - Depletion ring

private struct AIDepletionRing: View {
    let fraction: Double
    let tint: Color
    var dimension: CGFloat = 15

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "pause.fill")
                .font(.system(size: dimension * 0.34, weight: .black))
                .foregroundStyle(tint)
        }
        .frame(width: dimension, height: dimension)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

// MARK: - Panel

private struct AILimitPanel: View {
    @EnvironmentObject private var store: TurboTaskStore
    @Binding var isPresented: Bool

    @State private var expandedProvider: AIDependencyProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    ForEach(AIDependencyProvider.allCases) { provider in
                        providerRow(provider, now: context.date)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 360)
    }

    private var header: some View {
        let headerTint = store.activeAILimitProviders.first?.accent ?? TurboTheme.ink
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(headerTint.opacity(0.10))
                    .frame(width: 30, height: 30)
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.isAnyAILimitActive ? headerTint : TurboTheme.ink)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("AI limits")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                Text("Pause an assistant's tasks when it hits its cap")
                    .font(.system(size: 11))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Provider row

    @ViewBuilder
    private func providerRow(_ provider: AIDependencyProvider, now: Date) -> some View {
        let active = store.isAILimitActive(for: provider)
        let until = store.aiLimitHoldUntil(for: provider)
        let count = store.aiDependentOpenTaskCount(for: provider)
        let schedule = store.aiLimitSchedule(for: provider)
        let isExpanded = expandedProvider == provider
        let accent = provider.accent

        VStack(spacing: 0) {
            HStack(spacing: 11) {
                AIAgentIcon(provider: provider, size: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(provider.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TurboTheme.ink)
                        if count > 0 {
                            Text("· \(count)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(TurboTheme.mutedInk)
                        }
                    }
                    if active, let until {
                        Text("\(AICountdown.compact(until.timeIntervalSince(now))) · back \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    } else {
                        Text(scheduleSummary(schedule))
                            .font(.system(size: 11))
                            .foregroundStyle(TurboTheme.mutedInk)
                    }
                }

                Spacer(minLength: 6)

                actionButton(provider: provider, active: active, count: count)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        expandedProvider = isExpanded ? nil : provider
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit \(provider.title) reset schedule")
            }

            if isExpanded {
                scheduleEditor(provider: provider, schedule: schedule)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? accent.opacity(0.08) : TurboTheme.nestedCardFill.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(active ? accent.opacity(0.32) : TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func actionButton(provider: AIDependencyProvider, active: Bool, count: Int) -> some View {
        if active {
            Button {
                store.clearAILimitHold(for: provider)
            } label: {
                Text("Resume")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(AIPillButtonStyle(kind: .accent, tint: provider.accent))
            .help("Resume \(provider.title) tasks now")
        } else {
            Button {
                store.engageAILimit(for: provider)
            } label: {
                Text("Pause")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(AIPillButtonStyle(kind: .neutral))
            .disabled(count == 0)
            .opacity(count == 0 ? 0.4 : 1)
            .help(count == 0 ? "No open \(provider.title) tasks to pause" : "Hit your \(provider.title) cap? Pause its tasks until the next reset")
        }
    }

    // MARK: Schedule editor

    private func scheduleEditor(provider: AIDependencyProvider, schedule: AILimitSchedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Resets at")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                Spacer(minLength: 8)
                DatePicker("", selection: timeBinding(for: provider), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("On these days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                weekdayRow(provider: provider, schedule: schedule)
            }
        }
        .padding(.leading, 31)
    }

    private func weekdayRow(provider: AIDependencyProvider, schedule: AILimitSchedule) -> some View {
        let activeDays = schedule.resetWeekdays
        return HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { weekday in
                let label = Calendar.current.shortWeekdaySymbols[weekday - 1].prefix(1)
                let isOn = activeDays.isEmpty || activeDays.contains(weekday)

                Button {
                    toggleWeekday(weekday, for: provider)
                } label: {
                    Text(String(label))
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundStyle(isOn ? TurboTheme.sidebarSelectionInk : TurboTheme.mutedInk)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isOn ? TurboTheme.accent : TurboTheme.nestedCardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isOn ? Color.clear : TurboTheme.divider, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Schedule mutation

    private func timeBinding(for provider: AIDependencyProvider) -> Binding<Date> {
        Binding(
            get: {
                let schedule = store.aiLimitSchedule(for: provider)
                var components = DateComponents()
                components.hour = schedule.resetHour
                components.minute = schedule.resetMinute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                store.updateAILimitSchedule(for: provider) { schedule in
                    schedule.resetHour = parts.hour ?? schedule.resetHour
                    schedule.resetMinute = parts.minute ?? schedule.resetMinute
                }
            }
        )
    }

    private func toggleWeekday(_ weekday: Int, for provider: AIDependencyProvider) {
        store.updateAILimitSchedule(for: provider) { schedule in
            var set = Set(schedule.resetWeekdays)
            if set.isEmpty { set = Set(1...7) }
            if set.contains(weekday) {
                set.remove(weekday)
            } else {
                set.insert(weekday)
            }
            schedule.resetWeekdays = set.count == 7 ? [] : set.sorted()
        }
    }
}

// MARK: - Pill button style

private struct AIPillButtonStyle: ButtonStyle {
    enum Kind { case accent, neutral }
    var kind: Kind
    var tint: Color = .orange

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(foreground)
            .padding(.vertical, 6)
            .padding(.horizontal, 11)
            .background(
                Capsule()
                    .fill(fill(pressed: pressed))
                    .overlay(Capsule().stroke(stroke, lineWidth: 1))
            )
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .accent: tint
        case .neutral: TurboTheme.ink
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .accent: tint.opacity(pressed ? 0.28 : 0.18)
        case .neutral: TurboTheme.nestedCardFill.opacity(pressed ? 0.7 : 1)
        }
    }

    private var stroke: Color {
        switch kind {
        case .accent: tint.opacity(0.42)
        case .neutral: TurboTheme.cardStroke.opacity(0.9)
        }
    }
}
