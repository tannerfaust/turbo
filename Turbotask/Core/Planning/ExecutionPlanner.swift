//
//  ExecutionPlanner.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import Foundation

@MainActor
struct ExecutionPlan {
    var focusGroup: [TaskContext]
    var waiting: [TaskContext]
    var next: TaskContext?
    var deepFocusQueue: [TaskContext]
    var shallowQueue: [TaskContext]
    var multitaskQueue: [[TaskContext]]

    static let empty = ExecutionPlan(
        focusGroup: [],
        waiting: [],
        next: nil,
        deepFocusQueue: [],
        shallowQueue: [],
        multitaskQueue: []
    )
}

@MainActor
enum ExecutionPlanner {
    static func buildPlan(from tasks: [TaskContext]) -> ExecutionPlan {
        let ordered = tasks.sorted(by: sortByPriority)
        let waiting = ordered.filter { $0.task.status == .waiting }
        let queued = ordered.filter { $0.task.status == .queued || $0.task.status == .paused }
        let multitaskCandidates = ordered.filter {
            $0.task.energy.isMultitaskable && $0.task.status != .done && $0.task.status != .paused
        }
        let focusGroup = makeFocusGroup(ordered: ordered, queued: queued, multitaskCandidates: multitaskCandidates)
        let focusIDs = Set(focusGroup.map(\.task.id))

        let next = queued.first(where: { !focusIDs.contains($0.task.id) && !$0.task.energy.isMultitaskable })
            ?? queued.first(where: { !focusIDs.contains($0.task.id) })

        let deepFocusQueue = queued
            .filter { $0.task.energy == .deepFocus }

        let shallowQueue = queued
            .filter { $0.task.energy == .shallowWork }

        let multitaskQueue = makeGroups(from: multitaskCandidates.filter { !focusIDs.contains($0.task.id) })

        return ExecutionPlan(
            focusGroup: focusGroup,
            waiting: Array(waiting.filter { !focusIDs.contains($0.task.id) }.prefix(4)),
            next: next,
            deepFocusQueue: deepFocusQueue,
            shallowQueue: shallowQueue,
            multitaskQueue: multitaskQueue
        )
    }

    private static func makeFocusGroup(
        ordered: [TaskContext],
        queued: [TaskContext],
        multitaskCandidates: [TaskContext]
    ) -> [TaskContext] {
        let allActive = ordered.filter { $0.task.status == .active }

        if let exclusive = allActive.first(where: { !$0.task.energy.isMultitaskable }) {
            return [exclusive]
        }

        let activeMultitask = allActive.filter { $0.task.energy.isMultitaskable }
        if !activeMultitask.isEmpty {
            if isCompatible(group: activeMultitask) {
                return activeMultitask
            }
            return [activeMultitask[0]]
        }

        if let next = queued.first {
            guard next.task.energy.isMultitaskable else {
                return [next]
            }
            let compatibleQueued = queued.filter { $0.task.energy.isMultitaskable }
            return group(for: next, candidates: compatibleQueued)
        }

        return []
    }

    private static func group(for seed: TaskContext, candidates: [TaskContext]) -> [TaskContext] {
        var group = [seed]

        for candidate in candidates where candidate.task.id != seed.task.id {
            let proposed = group + [candidate]
            if isCompatible(group: proposed) {
                group.append(candidate)
            }
        }

        return group
    }

    private static func sortByPriority(lhs: TaskContext, rhs: TaskContext) -> Bool {
        if lhs.task.status == .active && rhs.task.status != .active {
            return true
        }

        if lhs.task.priority != rhs.task.priority {
            return lhs.task.priority > rhs.task.priority
        }

        if lhs.task.energy.maxParallelGroupSize != rhs.task.energy.maxParallelGroupSize {
            return lhs.task.energy.maxParallelGroupSize < rhs.task.energy.maxParallelGroupSize
        }

        return lhs.task.progress > rhs.task.progress
    }

    private static func makeGroups(from items: [TaskContext]) -> [[TaskContext]] {
        var groups: [[TaskContext]] = []
        var remaining = items

        while let seed = remaining.first {
            let group = group(for: seed, candidates: remaining)
            let ids = Set(group.map(\.task.id))
            groups.append(group)
            remaining.removeAll { ids.contains($0.task.id) }
        }

        return groups
    }

    private static func isCompatible(group: [TaskContext]) -> Bool {
        let groupSize = group.count
        return group.allSatisfy { context in
            context.task.energy.maxParallelGroupSize >= groupSize
        }
    }
}
