import SwiftUI

private enum WorkTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case operations = "Operations"
    var id: String { rawValue }
}

private enum OperationSort: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case open = "Open"
    case title = "Title"
    var id: String { rawValue }
}

struct WorkView: View {
    @State private var tab: WorkTab = .projects

    var body: some View {
        VStack(spacing: 0) {
            Picker("Work type", selection: $tab) {
                ForEach(WorkTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 240)
            .padding(.top, 14)
            .padding(.bottom, 2)

            switch tab {
            case .projects: ProjectsView()
            case .operations: OperationsView()
            }
        }
    }
}

private struct OperationsView: View {
    @EnvironmentObject private var store: TurboTaskStore
    @State private var focusedJobID: UUID?
    @State private var showArchived = false
    @State private var search = ""
    @State private var sort: OperationSort = .open
    @State private var selectedOperationID: UUID?
    @State private var pendingDelete: OperationContext?
    @State private var editingTask: TaskContext?

    private var operations: [OperationContext] {
        guard let focusedJobID else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = store.operationContexts(jobID: focusedJobID)
            .filter { $0.operation.isArchived == showArchived }
            .filter {
                query.isEmpty
                    || $0.operation.title.lowercased().contains(query)
                    || $0.operation.summary.lowercased().contains(query)
            }
        switch sort {
        case .manual:
            return filtered
        case .open:
            return filtered.sorted {
                if $0.openTaskCount != $1.openTaskCount { return $0.openTaskCount > $1.openTaskCount }
                return $0.operation.title.localizedCaseInsensitiveCompare($1.operation.title) == .orderedAscending
            }
        case .title:
            return filtered.sorted {
                $0.operation.title.localizedCaseInsensitiveCompare($1.operation.title) == .orderedAscending
            }
        }
    }

    private var selected: OperationContext? {
        operations.first(where: { $0.operation.id == selectedOperationID }) ?? operations.first
    }

    private var storeSelectedOperation: (jobID: UUID, operationID: UUID)? {
        guard case .operation(let jobID, let operationID) = store.selection else { return nil }
        return (jobID, operationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                fieldRail.frame(width: 216)
                Divider()
                operationList.frame(minWidth: 280, maxWidth: .infinity)
                Divider()
                inspector.frame(width: 308)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(TurboTheme.background)
        .onAppear {
            syncFocusedField()
            syncSelection(preferStoreSelection: true)
        }
        .onChange(of: store.jobs.map(\.id)) { _, _ in
            syncFocusedField()
            syncSelection(preferStoreSelection: true)
        }
        .onChange(of: store.selection) { _, _ in
            syncFocusedField()
            syncSelection(preferStoreSelection: true)
        }
        .onChange(of: focusedJobID) { _, _ in syncSelection() }
        .onChange(of: showArchived) { _, _ in syncSelection(preferStoreSelection: true) }
        .onChange(of: operations.map(\.id)) { _, _ in syncSelection(preferStoreSelection: true) }
        .alert("Delete operation?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    store.deleteOperation(jobID: pendingDelete.jobID, operationID: pendingDelete.operation.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes this operation, its tasks, and related history.")
        }
        .sheet(item: $editingTask) { TaskEditorDialog(context: $0).environmentObject(store) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OPERATIONS").font(.caption2.weight(.bold)).tracking(1.05).foregroundStyle(TurboTheme.mutedInk)
                Text("Ongoing work by field").font(.title2.weight(.semibold)).foregroundStyle(TurboTheme.ink)
            }
            Spacer()
            TextField("Filter operations…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            Picker("Sort", selection: $sort) {
                ForEach(OperationSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).frame(width: 100)
            Picker("Status", selection: $showArchived) {
                Text("Active").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 150)
            if let focusedJobID {
                Button("New operation") { store.openNewOperation(preferredJobID: focusedJobID) }
                    .buttonStyle(.borderedProminent).tint(TurboTheme.ink)
            }
        }
        .padding(.bottom, 16)
    }

    private var fieldRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fields").font(.caption2.weight(.semibold)).foregroundStyle(TurboTheme.mutedInk).padding(.horizontal, 12)
            List(store.jobs, selection: $focusedJobID) { job in
                HStack(spacing: 9) {
                    Circle().fill(job.palette.color).frame(width: 8, height: 8)
                    Text(job.title).lineLimit(1)
                    Spacer()
                    Text("\(store.operationCount(jobID: job.id))").font(.caption2).foregroundStyle(TurboTheme.mutedInk)
                }
                .tag(job.id)
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
        }
        .padding(.vertical, 8)
        .background(TurboTheme.nestedCardFill.opacity(0.35))
    }

    private var operationList: some View {
        Group {
            if store.jobs.isEmpty {
                TurboEmptyState(title: "Create a field first.", actionTitle: "New field") { store.openComposer(.job) }
            } else if operations.isEmpty {
                VStack(spacing: 10) {
                    Text(showArchived ? "No archived operations." : "No operations in this field.")
                        .foregroundStyle(TurboTheme.mutedInk)
                    if !showArchived { Button("New operation") { store.openNewOperation(preferredJobID: focusedJobID) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedOperationID) {
                    ForEach(operations) { context in
                        VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(context.jobColor)
                            Text(context.operation.title).font(.headline).lineLimit(1)
                            Spacer()
                            Text("\(context.openTaskCount) open").font(.caption).foregroundStyle(TurboTheme.mutedInk)
                        }
                        if !context.operation.summary.isEmpty {
                            Text(context.operation.summary).font(.caption).foregroundStyle(TurboTheme.mutedInk).lineLimit(2)
                        }
                    }
                        .padding(.vertical, 7)
                        .tag(context.operation.id)
                        .contextMenu {
                        Button(showArchived ? "Restore" : "Archive") {
                            store.setOperationArchived(jobID: context.jobID, operationID: context.operation.id, archived: !showArchived)
                        }
                        Divider()
                        Button("Delete", role: .destructive) { pendingDelete = context }
                        }
                    }
                    .onMove { source, destination in
                        guard sort == .manual,
                              search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let focusedJobID else { return }
                        store.moveOperations(jobID: focusedJobID, fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(TurboTheme.nestedCardFill.opacity(0.2))
    }

    @ViewBuilder
    private var inspector: some View {
        if let context = selected {
            OperationInspector(context: context, onEditTask: { editingTask = $0 }, onDelete: { pendingDelete = context })
                .environmentObject(store)
        } else {
            Text("Select an operation.").font(.caption).foregroundStyle(TurboTheme.mutedInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncFocusedField() {
        if let selected = storeSelectedOperation,
           store.operationContext(jobID: selected.jobID, operationID: selected.operationID) != nil {
            focusedJobID = selected.jobID
            return
        }

        if let focusedJobID, store.jobs.contains(where: { $0.id == focusedJobID }) {
            return
        }

        focusedJobID = store.selectedJobID.flatMap { selectedJobID in
            store.jobs.contains(where: { $0.id == selectedJobID }) ? selectedJobID : nil
        } ?? store.jobs.first?.id
    }

    private func syncSelection(preferStoreSelection: Bool = false) {
        if preferStoreSelection,
           let selected = storeSelectedOperation,
           selected.jobID == focusedJobID,
           operations.contains(where: { $0.operation.id == selected.operationID }) {
            selectedOperationID = selected.operationID
        } else if !operations.contains(where: { $0.operation.id == selectedOperationID }) {
            selectedOperationID = operations.first?.operation.id
        }

        if let selected = selected {
            store.select(.operation(jobID: selected.jobID, operationID: selected.operation.id))
        }
    }
}

private struct OperationInspector: View {
    @EnvironmentObject private var store: TurboTaskStore
    let context: OperationContext
    let onEditTask: (TaskContext) -> Void
    let onDelete: () -> Void

    private var tasks: [TaskContext] {
        store.taskContexts.filter { $0.operationID == context.operation.id && !$0.task.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Operation name", text: Binding(
                get: { context.operation.title },
                set: { value in store.updateOperation(jobID: context.jobID, operationID: context.operation.id) { $0.title = value } }
            ))
            .font(.title3.weight(.semibold)).textFieldStyle(.plain)

            TextField("Description", text: Binding(
                get: { context.operation.summary },
                set: { value in store.updateOperation(jobID: context.jobID, operationID: context.operation.id) { $0.summary = value } }
            ), axis: .vertical)
            .font(.caption).textFieldStyle(.plain).lineLimit(2...5)

            HStack {
                Text("Tasks").font(.caption.weight(.semibold)).foregroundStyle(TurboTheme.mutedInk)
                Spacer()
                Button { store.select(.operation(jobID: context.jobID, operationID: context.operation.id)); store.openComposer(.task) } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.plain).help("New task in this operation")
            }

            List(tasks) { task in
                HStack(alignment: .top) {
                    TaskStatusRowIndicator(status: task.task.status, jobColor: task.jobColor, diameter: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.task.title).lineLimit(1)
                        TaskSubtasksView(context: task, style: .list, maxVisible: 3)
                            .environmentObject(store)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onEditTask(task) }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)

            Divider()
            HStack {
                Button(context.operation.isArchived ? "Restore" : "Archive") {
                    store.setOperationArchived(jobID: context.jobID, operationID: context.operation.id, archived: !context.operation.isArchived)
                }
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .padding(14)
        .background(TurboTheme.nestedCardFill.opacity(0.35))
    }
}
