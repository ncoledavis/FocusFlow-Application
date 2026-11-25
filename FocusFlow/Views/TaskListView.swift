import SwiftUI

/// A live task list with an "Add task" button. The owner sees their own list;
/// a supporter sees the owner's list with only the controls their permission
/// allows.
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var isAddingTask = false

    private let access: TaskListAccess
    private let title: String

    /// - Parameters:
    ///   - ownerUid: Whose tasks to show.
    ///   - currentUid: Who is looking. Defaults to the owner.
    ///   - access: What they may do. Defaults to the owner's full access.
    ///   - title: The navigation title.
    init(
        repository: TaskRepository,
        ownerUid: String,
        currentUid: String? = nil,
        access: TaskListAccess = .owner,
        title: String = "My Tasks"
    ) {
        _viewModel = StateObject(
            wrappedValue: TaskListViewModel(
                repository: repository,
                ownerUid: ownerUid,
                currentUid: currentUid,
                access: access
            )
        )
        self.access = access
        self.title = title
    }

    var body: some View {
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.access.canAdd {
                        Button {
                            isAddingTask = true
                        } label: {
                            Label("Add task", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingTask) {
                AddTaskView(viewModel: viewModel)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.access.isSupporter {
                    roleBanner
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message, onDismiss: viewModel.clearError)
                }
            }
            .onChange(of: access) { _, newAccess in
                // The owner changed this supporter's permission while the list
                // was open.
                viewModel.access = newAccess
            }
            .task { viewModel.start() }
    }

    // MARK: - Content

    private var roleBanner: some View {
        Label(viewModel.access.roleDescription, systemImage: "person.2")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.allTasks.isEmpty {
            ProgressView("Loading tasks…")
        } else if viewModel.allTasks.isEmpty {
            emptyState
        } else {
            taskList
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.access.canAdd {
            ContentUnavailableView {
                Label("No tasks yet", systemImage: "checklist")
            } description: {
                Text(viewModel.access.isSupporter
                     ? "Add a task to help get things started."
                     : "Add your first task and give it a time budget.")
            } actions: {
                Button("Add task") { isAddingTask = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No tasks yet", systemImage: "checklist")
            } description: {
                Text("Tasks will show up here as they're added.")
            }
        }
    }

    private var taskList: some View {
        List {
            if !viewModel.activeTasks.isEmpty {
                Section("Up next") {
                    ForEach(viewModel.activeTasks) { task in
                        row(for: task)
                    }
                    .onDelete(perform: deleteAction(for: viewModel.activeTasks))
                }
            }
            if !viewModel.finishedTasks.isEmpty {
                Section("Finished") {
                    ForEach(viewModel.finishedTasks) { task in
                        row(for: task)
                    }
                    .onDelete(perform: deleteAction(for: viewModel.finishedTasks))
                }
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        TaskRow(task: task)
            .contextMenu {
                if viewModel.access.canReorder {
                    if task.status.isActive {
                        Button {
                            Task { await viewModel.move(task, .up) }
                        } label: {
                            Label("Move up", systemImage: "arrow.up")
                        }
                        Button {
                            Task { await viewModel.move(task, .down) }
                        } label: {
                            Label("Move down", systemImage: "arrow.down")
                        }
                    }
                    Menu("Change priority") {
                        ForEach(Priority.allCases) { priority in
                            Button(priority.title) {
                                Task { await viewModel.setPriority(priority, for: task) }
                            }
                        }
                    }
                }
                if viewModel.access.canModify {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.delete(task) }
                    }
                }
            }
    }

    /// Swipe-to-delete is only offered to people who may delete.
    private func deleteAction(for tasks: [TaskItem]) -> ((IndexSet) -> Void)? {
        guard viewModel.access.canModify else { return nil }
        return { offsets in
            let targets = offsets.map { tasks[$0] }
            Task {
                for task in targets {
                    await viewModel.delete(task)
                }
            }
        }
    }
}

/// One row in the task list: title, priority, and time budget.
private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.headline)
                .strikethrough(task.status == .done)

            HStack(spacing: 12) {
                Label(task.priority.title, systemImage: "flag.fill")
                    .foregroundStyle(priorityColor)
                if task.scheduleType == .fixed, let start = task.startAt, let finish = task.targetFinishAt {
                    Label(
                        "\(start.formatted(date: .abbreviated, time: .shortened)) – "
                            + finish.formatted(date: .omitted, time: .shortened),
                        systemImage: "calendar.clock"
                    )
                } else if let minutes = task.durationMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                }
                if task.status == .current {
                    Text("In progress")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                if !task.status.isActive {
                    Text(task.status.rawValue.capitalized)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if task.createdBy != task.ownerUid {
                Label("Added by a supporter", systemImage: "person.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

#Preview("With tasks") {
    NavigationStack {
        TaskListView(
            repository: MockTaskRepository(initialTasks: [
                TaskItem(id: "1", ownerUid: "me", title: "Write report", priority: .high,
                         durationMinutes: 45, createdBy: "me"),
                TaskItem(id: "2", ownerUid: "me", title: "Email advisor", priority: .low,
                         durationMinutes: 10, createdBy: "helper", order: 1)
            ]),
            ownerUid: "me"
        )
    }
}

#Preview("Supporter, view only") {
    NavigationStack {
        TaskListView(
            repository: MockTaskRepository(initialTasks: [
                TaskItem(id: "1", ownerUid: "me", title: "Write report", priority: .high,
                         durationMinutes: 45, createdBy: "me")
            ]),
            ownerUid: "me",
            currentUid: "helper",
            access: .supporter(.view),
            title: "alex@example.com"
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        TaskListView(repository: MockTaskRepository(), ownerUid: "me")
    }
}
