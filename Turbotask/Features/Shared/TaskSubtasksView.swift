//
//  TaskSubtasksView.swift
//  Turbotask
//
//  Compact subtask UI for task rows, cards, and composer/editor popovers.
//

import SwiftUI

enum TaskSubtasksDisplayStyle {
    case list
    case kanban
    case editor
}

struct TaskSubtasksView: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    var style: TaskSubtasksDisplayStyle = .list
    var maxVisible: Int? = nil

    private var visibleSubtasks: [TaskSubtask] {
        guard let maxVisible else { return context.task.subtasks }
        return Array(context.task.subtasks.prefix(maxVisible))
    }

    private var hiddenCount: Int {
        max(0, context.task.subtasks.count - visibleSubtasks.count)
    }

    private var isKanban: Bool {
        style == .kanban
    }

    var body: some View {
        if !context.task.subtasks.isEmpty {
            Group {
                if isKanban {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleSubtasks) { subtask in
                            subtaskChip(subtask)
                        }
                        if hiddenCount > 0 {
                            overflowLabel
                        }
                    }
                } else {
                    FlowLayout(spacing: 5) {
                        ForEach(visibleSubtasks) { subtask in
                            subtaskChip(subtask)
                        }
                        if hiddenCount > 0 {
                            overflowLabel
                        }
                    }
                }
            }
            .padding(.leading, style == .list ? 16 : 0)
            .padding(.top, isKanban ? 4 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var overflowLabel: some View {
        Text("+\(hiddenCount)")
            .font(.system(size: isKanban ? 9 : 10, weight: .semibold))
            .foregroundStyle(TurboTheme.mutedInk)
            .padding(.horizontal, 6)
            .padding(.vertical, isKanban ? 2 : 3)
            .background(Capsule().fill(TurboTheme.nestedCardFill.opacity(0.65)))
    }

    private func subtaskChip(_ subtask: TaskSubtask) -> some View {
        Button {
            store.setSubtaskDone(context: context, subtaskID: subtask.id, isDone: !subtask.isDone)
        } label: {
            HStack(spacing: isKanban ? 5 : 6) {
                ZStack {
                    Circle()
                        .fill(subtask.isDone ? context.jobColor.opacity(0.9) : context.jobColor.opacity(0.16))
                    if subtask.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: isKanban ? 6 : 7, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(context.jobColor.opacity(0.72))
                            .frame(width: isKanban ? 3 : 3.5, height: isKanban ? 3 : 3.5)
                    }
                }
                .frame(width: isKanban ? 12 : 13, height: isKanban ? 12 : 13)

                Text(subtask.title)
                    .font(.system(size: isKanban ? 10 : 11, weight: .medium))
                    .foregroundStyle(subtask.isDone ? TurboTheme.mutedInk.opacity(0.82) : TurboTheme.ink.opacity(0.86))
                    .strikethrough(subtask.isDone, color: TurboTheme.mutedInk.opacity(0.45))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, isKanban ? 6 : 7)
            .padding(.vertical, isKanban ? 3 : 4)
            .background(
                Capsule()
                    .fill(subtask.isDone ? TurboTheme.nestedCardFill.opacity(0.44) : context.jobColor.opacity(0.075))
            )
            .overlay(
                Capsule()
                    .stroke(subtask.isDone ? TurboTheme.cardStroke.opacity(0.34) : context.jobColor.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(subtask.isDone ? "Mark subtask incomplete" : "Complete subtask")
    }
}

struct TaskSubtasksPill: View {
    @Binding var subtasks: [TaskSubtask]

    var accentColor: Color

    @State private var isPresented = false

    private var title: String {
        if subtasks.isEmpty { return "Subtasks" }
        let done = subtasks.filter(\.isDone).count
        return "\(done)/\(subtasks.count) subtasks"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(subtasks.isEmpty ? TurboTheme.mutedInk : accentColor)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subtasks.isEmpty ? TurboTheme.mutedInk : TurboTheme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.75))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(TurboTheme.nestedCardFill))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1))
        .help("Create subtasks")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            TaskSubtasksPopoverEditor(subtasks: $subtasks, accentColor: accentColor)
                .frame(width: 340)
        }
    }
}

struct TaskSubtasksPopoverEditor: View {
    @Binding var subtasks: [TaskSubtask]

    @State private var draftTitle = ""

    var accentColor: Color

    private var canAdd: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && subtasks.count < Task.maxSubtasksPerTask
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                Text("Subtasks")
                    .font(.system(size: 13, weight: .semibold))
                if !subtasks.isEmpty {
                    Text("\(subtasks.filter(\.isDone).count)/\(subtasks.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if !subtasks.isEmpty {
                    ForEach($subtasks) { $subtask in
                        editorRow(subtask: $subtask)
                        if subtask.id != subtasks.last?.id {
                            Divider().opacity(0.5)
                                .padding(.leading, 34)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 18)
                    TextField("Add subtask", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit(addSubtask)
                    Button("Add", action: addSubtask)
                        .font(.system(size: 12, weight: .medium))
                        .disabled(!canAdd)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TurboTheme.nestedCardFill.opacity(0.45))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TurboTheme.cardStroke.opacity(0.55), lineWidth: 1)
            )
        }
        .padding(14)
        .background(TurboTheme.backgroundRaised)
    }

    private func editorRow(subtask: Binding<TaskSubtask>) -> some View {
        HStack(spacing: 8) {
            Button {
                subtask.wrappedValue.isDone.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(subtask.wrappedValue.isDone ? accentColor.opacity(0.95) : accentColor.opacity(0.14))
                    if subtask.wrappedValue.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(accentColor.opacity(0.72))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)

            TextField("Subtask title", text: subtask.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(subtask.wrappedValue.isDone ? TurboTheme.mutedInk : TurboTheme.ink)
                .strikethrough(subtask.wrappedValue.isDone, color: TurboTheme.mutedInk.opacity(0.45))

            Button {
                subtasks.removeAll { $0.id == subtask.wrappedValue.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Remove subtask")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private func addSubtask() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, subtasks.count < Task.maxSubtasksPerTask else { return }
        subtasks.append(TaskSubtask(title: title))
        draftTitle = ""
    }
}
