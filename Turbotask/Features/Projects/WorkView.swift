import SwiftUI

private enum WorkTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case operations = "Operations"
    var id: String { rawValue }
}

private enum OperationSort: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case open = "Most open"
    case title = "Name"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .manual: return "line.3.horizontal"
        case .open: return "chart.bar"
        case .title: return "textformat.abc"
        }
    }
}

struct WorkView: View {
    @State private var tab: WorkTab = .projects
    @Namespace private var tabNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkTabBar(tab: $tab, namespace: tabNamespace)
                .padding(.horizontal, 24)
                .padding(.top, 14)

            Rectangle()
                .fill(TurboTheme.divider.opacity(0.6))
                .frame(height: 1)

            switch tab {
            case .projects: ProjectsView()
            case .operations: OperationsView()
            }
        }
        .background(TurboTheme.background)
    }
}

// MARK: - Tab bar

private struct WorkTabBar: View {
    @Binding var tab: WorkTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 22) {
            ForEach(WorkTab.allCases) { item in
                tabButton(item)
            }
            Spacer(minLength: 0)
        }
    }

    private func tabButton(_ item: WorkTab) -> some View {
        let isActive = tab == item
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
        } label: {
            VStack(spacing: 8) {
                Text(item.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? TurboTheme.ink : TurboTheme.mutedInk)
                ZStack {
                    Capsule().fill(Color.clear).frame(height: 2)
                    if isActive {
                        Capsule()
                            .fill(TurboTheme.ink)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "workTabUnderline", in: namespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Operations

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

    private var focusedJob: Job? {
        focusedJobID.flatMap { id in store.jobs.first(where: { $0.id == id }) }
    }

    private var storeSelectedOperation: (jobID: UUID, operationID: UUID)? {
        guard case .operation(let jobID, let operationID) = store.selection else { return nil }
        return (jobID, operationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            content
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            fieldSelector
            searchField
            Spacer(minLength: 8)
            sortMenu
            statusToggle
            if focusedJobID != nil {
                Button {
                    store.openNewOperation(preferredJobID: focusedJobID)
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(TurboTheme.ink)
                .controlSize(.regular)
            }
        }
    }

    private var fieldSelector: some View {
        Menu {
            ForEach(store.jobs) { job in
                Button {
                    focusedJobID = job.id
                } label: {
                    Label {
                        Text("\(job.title)  ·  \(store.operationCount(jobID: job.id))")
                    } icon: {
                        Image(systemName: focusedJobID == job.id ? "checkmark" : "circle.fill")
                    }
                }
            }
            if store.jobs.isEmpty {
                Button("New field…") { store.openComposer(.job) }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(focusedJob?.palette.color ?? TurboTheme.mutedInk)
                    .frame(width: 8, height: 8)
                Text(focusedJob?.title ?? "Choose field")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TurboTheme.mutedInk)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TurboTheme.mutedInk)
            TextField("Search operations", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(TurboTheme.ink)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TurboTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private var sortMenu: some View {
        Menu {
            ForEach(OperationSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    Label(option.rawValue, systemImage: sort == option ? "checkmark" : option.symbol)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TurboTheme.mutedInk)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
        .help("Sort operations")
    }

    private var statusToggle: some View {
        HStack(spacing: 0) {
            segment("Active", active: !showArchived) { showArchived = false }
            segment("Archived", active: showArchived) { showArchived = true }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? TurboTheme.ink : TurboTheme.mutedInk)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? TurboTheme.cardFill : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(active ? TurboTheme.cardStroke.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty {
            TurboEmptyState(title: "Create a field first.", actionTitle: "New field") { store.openComposer(.job) }
            Spacer()
        } else {
            HStack(alignment: .top, spacing: 0) {
                operationList
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(TurboTheme.divider.opacity(0.6))
                    .frame(width: 1)
                inspector
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var operationList: some View {
        if operations.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.6))
                Text(showArchived ? "No archived operations." : "Nothing ongoing in this field.")
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                if !showArchived {
                    Button("New operation") { store.openNewOperation(preferredJobID: focusedJobID) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(operations) { context in
                    OperationRow(
                        context: context,
                        isSelected: selected?.operation.id == context.operation.id
                    )
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { select(context) }
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let context = selected {
            OperationInspector(context: context, onEditTask: { editingTask = $0 }, onDelete: { pendingDelete = context })
                .environmentObject(store)
                .padding(.leading, 18)
        } else {
            VStack(spacing: 6) {
                Text("Select an operation")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TurboTheme.mutedInk)
                Text("Pick one on the left to see its tasks.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func select(_ context: OperationContext) {
        selectedOperationID = context.operation.id
        store.select(.operation(jobID: context.jobID, operationID: context.operation.id))
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

// MARK: - Operation row

private struct OperationRow: View {
    let context: OperationContext
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isSelected ? context.jobColor : context.jobColor.opacity(0.45))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(context.operation.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(TurboTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    countChip
                }
                if !context.operation.summary.isEmpty {
                    Text(context.operation.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? TurboTheme.rowSelected : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? TurboTheme.cardStroke.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }

    private var countChip: some View {
        Text("\(context.openTaskCount)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(context.openTaskCount > 0 ? TurboTheme.ink : TurboTheme.mutedInk)
            .frame(minWidth: 18)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(TurboTheme.nestedCardFill)
                    .overlay(Capsule().stroke(TurboTheme.cardStroke.opacity(0.7), lineWidth: 1))
            )
            .help("\(context.openTaskCount) open tasks")
    }
}

// MARK: - Inspector

private struct OperationInspector: View {
    @EnvironmentObject private var store: TurboTaskStore
    let context: OperationContext
    let onEditTask: (TaskContext) -> Void
    let onDelete: () -> Void

    private var tasks: [TaskContext] {
        store.taskContexts.filter { $0.operationID == context.operation.id && !$0.task.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(context.jobColor).frame(width: 8, height: 8)
                    Text(context.jobTitle.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(TurboTheme.mutedInk)
                }

                TextField("Operation name", text: Binding(
                    get: { context.operation.title },
                    set: { value in store.updateOperation(jobID: context.jobID, operationID: context.operation.id) { $0.title = value } }
                ))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TurboTheme.ink)
                .textFieldStyle(.plain)

                TextField("Add a description…", text: Binding(
                    get: { context.operation.summary },
                    set: { value in store.updateOperation(jobID: context.jobID, operationID: context.operation.id) { $0.summary = value } }
                ), axis: .vertical)
                .font(.system(size: 12.5))
                .foregroundStyle(TurboTheme.mutedInk)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
            }

            Rectangle().fill(TurboTheme.divider.opacity(0.6)).frame(height: 1)

            HStack {
                Text("TASKS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(TurboTheme.mutedInk)
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
                Spacer()
                Button {
                    store.select(.operation(jobID: context.jobID, operationID: context.operation.id))
                    store.openComposer(.task)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TurboTheme.mutedInk)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(TurboTheme.nestedCardFill)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(TurboTheme.cardStroke.opacity(0.7), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .help("New task in this operation")
            }

            if tasks.isEmpty {
                Text("No tasks yet.")
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { task in
                            HStack(alignment: .top, spacing: 9) {
                                TaskStatusRowIndicator(status: task.task.status, jobColor: task.jobColor, diameter: 14)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.task.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(TurboTheme.ink)
                                        .lineLimit(2)
                                    TaskSubtasksView(context: task, style: .list, maxVisible: 3)
                                        .environmentObject(store)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onEditTask(task) }
                            if task.id != tasks.last?.id {
                                Rectangle().fill(TurboTheme.divider.opacity(0.4)).frame(height: 1)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Rectangle().fill(TurboTheme.divider.opacity(0.6)).frame(height: 1)
            HStack {
                Button(context.operation.isArchived ? "Restore" : "Archive") {
                    store.setOperationArchived(jobID: context.jobID, operationID: context.operation.id, archived: !context.operation.isArchived)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk)
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TurboTheme.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
