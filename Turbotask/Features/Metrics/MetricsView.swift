//
//  MetricsView.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct MetricsView: View {
    @EnvironmentObject private var store: TurboTaskStore

    private var week: [ActivitySummary] {
        store.activitySummary(daysBack: 7)
    }

    private var openTasks: Int {
        store.openTaskCount
    }

    private var inProgress: Int {
        store.activeTasks.count
    }

    private var finishedThisWeek: Int {
        week.reduce(0) { $0 + $1.completions }
    }

    private var todayDone: Int {
        week.last?.completions ?? 0
    }

    private var weekBarMax: Int {
        max(week.map(\.completions).max() ?? 0, 1)
    }

    private var recentCompletions: [ActivityEvent] {
        Array(store.history.filter { $0.kind == .completed }.prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                statStrip

                archiveStatusCard

                if store.workedMinutesToday > 0 {
                    todayTimeLine
                }

                weekChart

                if !recentCompletions.isEmpty {
                    recentFinishes
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TurboTheme.background)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.completionCount)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(TurboTheme.ink)
                .contentTransition(.numericText())
                .accessibilityLabel("\(store.completionCount) tasks marked done in your workspace")

            HStack(spacing: 6) {
                Text("tasks done")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                TurboInfoButton(
                    title: "Completion total",
                    message: "Lifetime total counts every completion, including tasks later removed from the archive."
                )
            }

            if finishedThisWeek > 0 {
                Text("\(finishedThisWeek) finished in the last 7 days")
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(value: openTasks, label: "open", hint: "Tasks not done yet")
            statDivider
            statCell(value: store.waitingTaskCount, label: "waiting", hint: "Waiting on something")
            statDivider
            statCell(value: todayDone, label: "today", hint: "Completed today")
            statDivider
            statCell(value: inProgress, label: "active", hint: "In progress now")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TurboTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TurboTheme.cardStroke, lineWidth: 1)
                )
        )
    }

    private var archiveStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Archive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                TurboInfoButton(
                    title: "Archive metrics",
                    message: archiveInfoMessage
                )
                Spacer(minLength: 0)
                Text("\(store.archivedTaskContexts.count) tasks")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var statDivider: some View {
        Rectangle()
            .fill(TurboTheme.divider)
            .frame(width: 1)
            .frame(maxHeight: 36)
    }

    private var archiveInfoMessage: String {
        if store.archivedTaskPurgeAfterDays > 0 {
            return "Auto-delete archived tasks after \(store.archivedTaskPurgeAfterDays) days. Done and focus events stay in this dashboard."
        }
        return "Open Archive in the sidebar to review or restore. Purge timing is in Settings."
    }

    private func statCell(value: Int, label: String, hint: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TurboTheme.ink)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(value) \(label), \(hint)")
    }

    private var todayTimeLine: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(TurboTheme.accent.opacity(0.85))
                .frame(width: 4, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                Text(formatMinutes(store.workedMinutesToday))
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TurboTheme.accentSoft.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week) { day in
                    weekBar(for: day)
                }
            }
            .frame(height: 88)
        }
        .accessibilityLabel("Completions per day over the last week")
    }

    private func weekBar(for day: ActivitySummary) -> some View {
        let ratio = CGFloat(day.completions) / CGFloat(weekBarMax)
        let barH = max(6, ratio * 72)

        return VStack(spacing: 8) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TurboTheme.accent.opacity(0.35 + 0.5 * ratio),
                            TurboTheme.accent.opacity(0.55 + 0.35 * ratio)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: barH)
                .accessibilityLabel("\(day.completions) on \(day.date.formatted(.dateTime.weekday(.wide)))")

            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentFinishes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent finishes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TurboTheme.mutedInk)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recentCompletions.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.taskTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(TurboTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(TurboTheme.mutedInk)
                            .layoutPriority(1)
                    }
                    .padding(.vertical, 10)

                    if index < recentCompletions.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        if m >= 60 {
            let h = m / 60
            let r = m % 60
            return r == 0 ? "\(h)h focus logged" : "\(h)h \(r)m logged"
        }
        return "\(m)m logged"
    }
}
