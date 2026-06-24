//
//  ArchiveView.swift
//  Turbotask
//

import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var store: TurboTaskStore
    @State private var search = ""
    @State private var editingTask: TaskContext?

    private var visible: [TaskContext] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = store.archivedTaskContexts
        guard !q.isEmpty else { return base }
        return base.filter { ctx in
            ctx.task.title.lowercased().contains(q)
                || ctx.task.summary.lowercased().contains(q)
                || ctx.jobTitle.lowercased().contains(q)
                || ctx.projectTitle.lowercased().contains(q)
                || ctx.operationTitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)

            searchRow
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            Group {
                if visible.isEmpty {
                    TurboEmptyState(
                        title: search.isEmpty
                            ? "Nothing in the archive."
                            : "No archived tasks match your search.",
                        actionTitle: search.isEmpty ? "Go to Tasks" : "Clear search",
                        action: {
                            if search.isEmpty {
                                store.selectedScreen = .tasks
                            } else {
                                search = ""
                            }
                        }
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible) { ctx in
                                ArchiveTaskRow(
                                    context: ctx,
                                    isSelected: isSelected(ctx),
                                    onSelect: { select(ctx) },
                                    onEdit: { editingTask = ctx }
                                )
                                .environmentObject(store)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(TurboTheme.background)
        .sheet(item: $editingTask) { context in
            TaskEditorDialog(context: context)
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ARCHIVE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TurboTheme.mutedInk)
                .tracking(1.1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Archived tasks")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                Spacer(minLength: 8)
                Text("\(visible.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(TurboTheme.ink.opacity(0.22))
                    .contentTransition(.numericText())
            }
            Text(
                store.archivedTaskPurgeAfterDays > 0
                    ? "Auto-delete after \(store.archivedTaskPurgeAfterDays) days in archive (change in Settings). Completions stay in Metrics."
                    : "Restore, edit, or delete permanently. Completions stay in Metrics when you delete."
            )
            .font(.caption)
            .foregroundStyle(TurboTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            TextField("Search archived tasks…", text: $search)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TurboTheme.backgroundRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(TurboTheme.cardStroke.opacity(0.5), lineWidth: 1)
                        )
                )
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TurboTheme.nestedCardFill.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func isSelected(_ ctx: TaskContext) -> Bool {
        if case let .task(j, p, tid) = store.selection {
            return tid == ctx.task.id && j == ctx.jobID && p == ctx.projectID
        }
        return false
    }

    private func select(_ ctx: TaskContext) {
        store.selectTask(ctx)
    }
}

// MARK: - Row

private struct ArchiveTaskRow: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    private var archivedLine: String {
        if let d = context.task.archivedAt {
            return "Archived \(d.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Archived (date unknown)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(context.jobColor)
                .frame(width: 3)

            HStack(alignment: .center, spacing: 10) {
                TaskStatusRowIndicator(
                    status: context.task.status,
                    jobColor: context.jobColor,
                    diameter: 15
                )

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onSelect) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.task.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TurboTheme.ink)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)

                            Text(metaLine)
                                .font(.caption2)
                                .foregroundStyle(TurboTheme.mutedInk)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    TaskSubtasksView(context: context, style: .list, maxVisible: 3)
                        .environmentObject(store)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
        }
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TurboTheme.divider.opacity(0.22))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            store.selectTask(context)
            onEdit()
        }
        .contextMenu {
            TaskRowContextMenuItems(context: context, onEdit: onEdit)
                .environmentObject(store)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !context.jobTitle.isEmpty { parts.append(context.jobTitle) }
        if !context.projectTitle.isEmpty { parts.append(context.projectTitle) }
        if !context.operationTitle.isEmpty { parts.append(context.operationTitle) }
        let scope = parts.isEmpty ? "Inbox" : parts.joined(separator: " · ")
        return "\(archivedLine) · \(scope) · \(context.task.status.title)"
    }

    private var rowBackground: Color {
        if isSelected {
            return TurboTheme.accentSoft.opacity(0.52)
        }
        return Color.clear
    }
}
