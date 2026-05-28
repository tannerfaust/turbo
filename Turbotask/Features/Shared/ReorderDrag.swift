//
//  ReorderDrag.swift
//  Turbotask
//
//  Reusable drag-and-drop reorder infrastructure used across all pages.
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ReorderDragState: ObservableObject {
    @Published var draggedID: UUID?
    @Published var hoverTargetID: UUID?
    @Published var hoverIsEnd = false

    func reset() {
        draggedID = nil
        hoverTargetID = nil
        hoverIsEnd = false
    }
}

struct ReorderDropLine: View {
    var body: some View {
        Rectangle()
            .fill(TurboTheme.accent)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ReorderHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(TurboTheme.mutedInk)
            .frame(width: 16, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder")
    }
}

struct RowReorderDropDelegate: DropDelegate {
    let rowID: UUID
    let drag: ReorderDragState
    let onMoveBefore: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        drag.draggedID != nil && drag.draggedID != rowID
    }

    func dropEntered(info: DropInfo) {
        guard let id = drag.draggedID, id != rowID else { return }
        drag.hoverIsEnd = false
        drag.hoverTargetID = rowID
    }

    func dropExited(info: DropInfo) {
        if drag.hoverTargetID == rowID { drag.hoverTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedID, movingID != rowID else {
            drag.reset()
            return false
        }
        drag.reset()
        onMoveBefore(movingID)
        return true
    }
}

struct EndReorderDropDelegate: DropDelegate {
    let drag: ReorderDragState
    let onMoveToEnd: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.draggedID != nil }

    func dropEntered(info: DropInfo) {
        guard drag.draggedID != nil else { return }
        drag.hoverTargetID = nil
        drag.hoverIsEnd = true
    }

    func dropExited(info: DropInfo) { drag.hoverIsEnd = false }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let movingID = drag.draggedID else {
            drag.reset()
            return false
        }
        drag.reset()
        onMoveToEnd(movingID)
        return true
    }
}
