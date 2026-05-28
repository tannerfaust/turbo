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
}
