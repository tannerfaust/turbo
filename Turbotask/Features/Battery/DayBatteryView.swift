//
//  DayBatteryView.swift
//  Turbotask
//
//  Created by Codex on 13.04.2026.
//

import SwiftUI

struct DayBatteryView: View {
    @EnvironmentObject private var store: TurboTaskStore
    @Environment(\.calendar) private var calendar
    @ObservedObject private var clock = DayBatteryClock.shared
    @State private var startSelection = Date.now
    @State private var endSelection = Date.now
    @State private var showsPercentageInMenuBar = true
    @State private var usesWideMenuBarItem = false

    var body: some View {
        let status = DayBatteryStatus(
            now: clock.now,
            startMinutes: store.dayBatteryStartMinutes,
            endMinutes: store.dayBatteryEndMinutes,
            calendar: calendar
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TurboPageHeader(
                    title: "Day Battery",
                    trailing: AnyView(
                        TurboTag(text: status.phaseTitle, tint: status.tint)
                    )
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        DayBatteryHeroCard(status: status)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 20) {
                            DayBatterySetupCard(
                                startSelection: $startSelection,
                                endSelection: $endSelection,
                                showsPercentageInMenuBar: $showsPercentageInMenuBar,
                                usesWideMenuBarItem: $usesWideMenuBarItem
                            )
                            DayBatteryInsightCard(status: status)
                        }
                        .frame(width: 340)
                    }

                    VStack(spacing: 20) {
                        DayBatteryHeroCard(status: status)
                        DayBatterySetupCard(
                            startSelection: $startSelection,
                            endSelection: $endSelection,
                            showsPercentageInMenuBar: $showsPercentageInMenuBar,
                            usesWideMenuBarItem: $usesWideMenuBarItem
                        )
                        DayBatteryInsightCard(status: status)
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(TurboTheme.background)
        .onAppear {
            clock.start()
            syncDraftsFromStore()
        }
        .onChange(of: startSelection) { _, newValue in
            let minutes = minutesFromTimeSelection(newValue)
            guard minutes != store.dayBatteryStartMinutes else { return }
            _Concurrency.Task { @MainActor in
                store.setDayBatteryStartMinutes(minutes)
            }
        }
        .onChange(of: endSelection) { _, newValue in
            let minutes = minutesFromTimeSelection(newValue)
            guard minutes != store.dayBatteryEndMinutes else { return }
            _Concurrency.Task { @MainActor in
                store.setDayBatteryEndMinutes(minutes)
            }
        }
        .onChange(of: showsPercentageInMenuBar) { _, newValue in
            guard newValue != store.dayBatteryShowsPercentageInMenuBar else { return }
            _Concurrency.Task { @MainActor in
                store.setDayBatteryShowsPercentageInMenuBar(newValue)
            }
        }
        .onChange(of: usesWideMenuBarItem) { _, newValue in
            guard newValue != store.dayBatteryUsesWideMenuBarItem else { return }
            _Concurrency.Task { @MainActor in
                store.setDayBatteryUsesWideMenuBarItem(newValue)
            }
        }
        .onChange(of: store.dayBatteryStartMinutes) { _, _ in
            syncDraftsFromStore()
        }
        .onChange(of: store.dayBatteryEndMinutes) { _, _ in
            syncDraftsFromStore()
        }
        .onChange(of: store.dayBatteryShowsPercentageInMenuBar) { _, _ in
            syncDraftsFromStore()
        }
        .onChange(of: store.dayBatteryUsesWideMenuBarItem) { _, _ in
            syncDraftsFromStore()
        }
    }

    private func dateForTimeSelection(minutes: Int) -> Date {
        let dayStart = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minutes, to: dayStart) ?? dayStart
    }

    private func minutesFromTimeSelection(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ((parts.hour ?? 0) * 60) + (parts.minute ?? 0)
    }

    private func syncDraftsFromStore() {
        let syncedStart = dateForTimeSelection(minutes: store.dayBatteryStartMinutes)
        let syncedEnd = dateForTimeSelection(minutes: store.dayBatteryEndMinutes)

        if !calendar.isDate(startSelection, equalTo: syncedStart, toGranularity: .minute) {
            startSelection = syncedStart
        }
        if !calendar.isDate(endSelection, equalTo: syncedEnd, toGranularity: .minute) {
            endSelection = syncedEnd
        }
        if showsPercentageInMenuBar != store.dayBatteryShowsPercentageInMenuBar {
            showsPercentageInMenuBar = store.dayBatteryShowsPercentageInMenuBar
        }
        if usesWideMenuBarItem != store.dayBatteryUsesWideMenuBarItem {
            usesWideMenuBarItem = store.dayBatteryUsesWideMenuBarItem
        }
    }
}

private struct DayBatteryHeroCard: View {
    let status: DayBatteryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.primaryLine)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(TurboTheme.ink)
                    .monospacedDigit()

                Text(status.secondaryLine)
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
            }

            DayBatteryGauge(status: status)
                .frame(height: 220)

            HStack(spacing: 12) {
                metricColumn(title: "Window", value: status.windowLabel)
                metricColumn(title: "Elapsed", value: status.elapsedLabel)
                metricColumn(title: "Left", value: status.remainingLabel)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            status.tint.opacity(0.18),
                            TurboTheme.cardFill.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1)
                )
        )
    }

    private func metricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.75), lineWidth: 1)
                )
        )
    }
}

private struct DayBatteryGauge: View {
    let status: DayBatteryStatus

    var body: some View {
        GeometryReader { proxy in
            let tipWidth = min(26.0, max(18.0, proxy.size.width * 0.04))
            let bodyWidth = max(proxy.size.width - tipWidth - 14, 0)

            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(TurboTheme.background.opacity(0.68))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(status.tint.opacity(0.28), lineWidth: 2)
                        )

                    if status.charge > 0 {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(fillGradient)
                            .frame(width: max((bodyWidth - 20) * status.charge, 22))
                            .padding(10)
                    }

                    HStack(spacing: 0) {
                        ForEach(1..<4) { index in
                            Spacer()
                            Rectangle()
                                .fill(TurboTheme.cardStroke.opacity(0.6))
                                .frame(width: 1)
                                .padding(.vertical, 18)
                            Spacer()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(status.chargePercentLabel)
                            .font(.system(size: 50, weight: .black, design: .rounded))
                            .foregroundStyle(TurboTheme.ink)
                            .monospacedDigit()

                        Text(status.gaugeCaption)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(TurboTheme.mutedInk)
                    }
                    .padding(.horizontal, 26)
                }
                .frame(width: bodyWidth)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        status.charge > 0.02
                            ? status.tint.opacity(0.92)
                            : TurboTheme.cardStroke.opacity(0.6)
                    )
                    .frame(width: tipWidth, height: proxy.size.height * 0.34)
            }
        }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                status.tint.opacity(0.96),
                status.tint.opacity(0.58)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct DayBatterySetupCard: View {
    @Binding var startSelection: Date
    @Binding var endSelection: Date
    @Binding var showsPercentageInMenuBar: Bool
    @Binding var usesWideMenuBarItem: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Setup")
                    .font(.headline)
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Battery window",
                    message: "Set when your planned day starts and ends. If the end time is earlier than the start time, the battery runs overnight into the next day."
                )
                Spacer(minLength: 0)
            }

            DatePicker("Starts", selection: $startSelection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            DatePicker("Ends", selection: $endSelection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: 6) {
                Text("Menu bar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Menu bar display",
                    message: "Turn the number off for a cleaner icon-only battery. Turn wider battery on if you want the menu bar shape to read more like a full battery instead of a compact badge."
                )
                Spacer(minLength: 0)
            }

            Toggle("Show percentage", isOn: $showsPercentageInMenuBar)
                .toggleStyle(.switch)

            Toggle("Wider battery", isOn: $usesWideMenuBarItem)
                .toggleStyle(.switch)
        }
        .padding(20)
        .turboCard()
    }
}

private struct DayBatteryInsightCard: View {
    let status: DayBatteryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Readout")
                    .font(.headline)
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Readout",
                    message: status.detailFootnote
                )
                Spacer(minLength: 0)
            }

            TurboMetricPill(label: "Next shift", value: status.nextBoundaryLabel)
            TurboMetricPill(label: "Current state", value: status.phaseDescription)
            TurboMetricPill(label: "Progress", value: status.progressText)
        }
        .padding(20)
        .turboCard()
    }
}

struct DayBatteryStatus {
    enum Phase {
        case upcoming
        case active
        case ended
    }

    let phase: Phase
    let charge: Double
    let elapsedFraction: Double
    let tint: Color
    let primaryLine: String
    let secondaryLine: String
    let phaseTitle: String
    let phaseDescription: String
    let windowLabel: String
    let elapsedLabel: String
    let remainingLabel: String
    let gaugeCaption: String
    let progressText: String
    let detailFootnote: String
    let nextBoundaryLabel: String
    let chargePercentLabel: String

    init(now: Date, startMinutes: Int, endMinutes: Int, calendar: Calendar) {
        let todayStart = calendar.startOfDay(for: now)
        let durationMinutes = Self.normalizedDurationMinutes(startMinutes: startMinutes, endMinutes: endMinutes)
        let durationSeconds = TimeInterval(durationMinutes * 60)
        let startToday = calendar.date(byAdding: .minute, value: startMinutes, to: todayStart) ?? todayStart
        let activeWindow = [-1, 0, 1]
            .compactMap { calendar.date(byAdding: .day, value: $0, to: startToday) }
            .compactMap { start -> (Date, Date)? in
                let end = start.addingTimeInterval(durationSeconds)
                return (start, end)
            }
            .first(where: { now >= $0.0 && now < $0.1 })

        let formatter = Self.timeFormatter
        let durationLabel = Self.compactDurationLabel(durationSeconds)
        let windowLabel = "\(formatter.string(from: startToday)) - \(formatter.string(from: startToday.addingTimeInterval(durationSeconds)))"

        if let activeWindow {
            let remaining = max(activeWindow.1.timeIntervalSince(now), 0)
            let elapsed = max(now.timeIntervalSince(activeWindow.0), 0)
            let fractionRemaining = min(max(remaining / durationSeconds, 0), 1)
            let fractionElapsed = min(max(elapsed / durationSeconds, 0), 1)
            let tint = Self.tintForActiveCharge(fractionRemaining)

            phase = .active
            charge = fractionRemaining
            elapsedFraction = fractionElapsed
            self.tint = tint
            primaryLine = "\(Self.compactDurationLabel(remaining)) left"
            secondaryLine = "Battery is draining through your planned day window."
            phaseTitle = "Live"
            phaseDescription = "Active right now"
            self.windowLabel = windowLabel
            elapsedLabel = Self.compactDurationLabel(elapsed)
            remainingLabel = Self.compactDurationLabel(remaining)
            gaugeCaption = "of today still available"
            progressText = "\(Int(round(fractionElapsed * 100)))% used"
            detailFootnote = "Your battery runs for \(durationLabel) every cycle. When it empties, the next battery starts at \(formatter.string(from: Self.nextStart(after: activeWindow.0, calendar: calendar)))."
            nextBoundaryLabel = formatter.string(from: activeWindow.1)
            chargePercentLabel = "\(Int(round(fractionRemaining * 100)))%"
            return
        }

        if now < startToday {
            let untilStart = startToday.timeIntervalSince(now)
            phase = .upcoming
            charge = 1
            elapsedFraction = 0
            tint = TurboTheme.accent
            primaryLine = "Starts in \(Self.compactDurationLabel(untilStart))"
            secondaryLine = "Full battery waiting for the next work window."
            phaseTitle = "Waiting"
            phaseDescription = "Before today’s window"
            self.windowLabel = windowLabel
            elapsedLabel = "0m"
            remainingLabel = durationLabel
            gaugeCaption = "available once the window starts"
            progressText = "0% used"
            detailFootnote = "Current setup gives you a \(durationLabel) battery each day. The next discharge begins at \(formatter.string(from: startToday))."
            nextBoundaryLabel = formatter.string(from: startToday)
            chargePercentLabel = "100%"
            return
        }

        let nextStart = Self.nextStart(after: startToday, calendar: calendar)
        let untilNextStart = nextStart.timeIntervalSince(now)
        phase = .ended
        charge = 0
        elapsedFraction = 1
        tint = TurboTheme.mutedInk.opacity(0.9)
        primaryLine = "Battery empty"
        secondaryLine = "That work window is over. The next one starts later."
        phaseTitle = "Empty"
        phaseDescription = "After today’s window"
        self.windowLabel = windowLabel
        elapsedLabel = durationLabel
        remainingLabel = "0m"
        gaugeCaption = "left in the current window"
        progressText = "100% used"
        detailFootnote = "The current battery was \(durationLabel) long. It refills in \(Self.compactDurationLabel(untilNextStart)) at \(formatter.string(from: nextStart))."
        nextBoundaryLabel = formatter.string(from: nextStart)
        chargePercentLabel = "0%"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func nextStart(after start: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    private static func normalizedDurationMinutes(startMinutes: Int, endMinutes: Int) -> Int {
        if startMinutes == endMinutes {
            return 24 * 60
        }
        if endMinutes > startMinutes {
            return endMinutes - startMinutes
        }
        return (24 * 60 - startMinutes) + endMinutes
    }

    private static func compactDurationLabel(_ interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval.rounded(.down) / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        switch (hours, minutes) {
        case (0, _):
            return "\(minutes)m"
        case (_, 0):
            return "\(hours)h"
        default:
            return "\(hours)h \(minutes)m"
        }
    }

    private static func tintForActiveCharge(_ charge: Double) -> Color {
        switch charge {
        case 0.6...:
            return Color.green.opacity(0.92)
        case 0.3...:
            return Color.orange.opacity(0.92)
        default:
            return Color.red.opacity(0.88)
        }
    }
}
