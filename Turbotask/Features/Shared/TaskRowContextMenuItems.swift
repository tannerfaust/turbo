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

            Divider()

            Button(role: .destructive) {
                store.deleteTask(context: context)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }
}
