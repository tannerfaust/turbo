//
//  TaskRowContextMenuItems.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

/// Shared menu entries for secondary click (context menu) on task rows.
struct TaskRowContextMenuItems: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TaskContext
    /// When set, shows Edit and selects the task before editing.
    var onEdit: (() -> Void)?

    var body: some View {
        Group {
            if let onEdit {
                Button {
                    store.selectTask(context)
                    onEdit()
                } label: {
                    Label("Edit Task", systemImage: "pencil")
                }
                Divider()
            }

            Button {
                store.selectTask(context)
                store.toggleTaskNow(context)
            } label: {
                Label(
                    context.task.isScheduledNow ? "Remove from Now" : "Pin to Now",
                    systemImage: context.task.isScheduledNow ? "pin.slash" : "pin"
                )
            }

            Menu {
                ForEach(TaskEnergy.allCases) { energy in
                    Button {
                        store.setTaskEnergy(context, energy: energy)
                    } label: {
                        HStack {
                            Text(energy.title)
                            if context.task.energy == energy {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Change Type", systemImage: "arrow.triangle.swap")
            }

            Menu {
                let candidates = dependencyFollowUpCandidates
                if candidates.isEmpty {
                    Text("No tasks available")
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            store.addTaskDependency(prerequisiteID: context.task.id, dependentID: candidate.task.id)
                        } label: {
                            Text(candidate.task.title)
                        }
                    }
                }
            } label: {
                Label("Unlocks when done…", systemImage: "arrow.turn.down.right")
            }

            if !context.task.blockedByTaskIDs.isEmpty {
                Menu("Remove prerequisite…") {
                    ForEach(context.task.blockedByTaskIDs, id: \.self) { blockerID in
                        Button {
                            store.removeTaskDependency(prerequisiteID: blockerID, from: context.task.id)
                        } label: {
                            Text(store.taskContext(taskID: blockerID)?.task.title ?? "Task")
                        }
                    }
                }
            }

            if context.task.isArchived {
                Button {
                    store.selectTask(context)
                    store.setTaskArchived(context, archived: false)
                } label: {
                    Label("Restore from archive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    store.selectTask(context)
                    store.setTaskArchived(context, archived: true)
                } label: {
                    Label("Archive task", systemImage: "archivebox")
                }
            }

            Divider()

            Button(role: .destructive) {
                store.deleteTask(context: context)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private var dependencyFollowUpCandidates: [TaskContext] {
        store.taskContexts.filter { candidate in
            candidate.task.id != context.task.id
                && !candidate.task.isArchived
                && !candidate.task.blockedByTaskIDs.contains(context.task.id)
        }
        .sorted { $0.task.title.localizedCaseInsensitiveCompare($1.task.title) == .orderedAscending }
    }
}
