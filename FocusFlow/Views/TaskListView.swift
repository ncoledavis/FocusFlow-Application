import SwiftUI

/// The signed-in user's live task list, with an "Add task" button.
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var isAddingTask = false

    init(repository: TaskRepository, ownerUid: String) {
        _viewModel = StateObject(
            wrappedValue: TaskListViewModel(repository: repository, ownerUid: ownerUid)
        )
    }

    var body: some View {
        content
            .navigationTitle("My Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAddingTask = true
                    } label: {
                        Label("Add task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingTask) {
                AddTaskView(viewModel: viewModel)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.errorMessage {
                    errorBanner(message)
                }
            }
            .task { viewModel.start() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.allTasks.isEmpty {
            ProgressView("Loading tasks…")
        } else if viewModel.allTasks.isEmpty {
            ContentUnavailableView {
                Label("No tasks yet", systemImage: "checklist")
            } description: {
                Text("Add your first task and give it a time budget.")
            } actions: {
                Button("Add task") { isAddingTask = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            taskList
        }
    }

    private var taskList: some View {
        List {
            if !viewModel.activeTasks.isEmpty {
                Section("Up next") {
                    ForEach(viewModel.activeTasks) { task in
                        row(for: task)
                    }
                    .onDelete { offsets in
                        delete(at: offsets, in: viewModel.activeTasks)
                    }
                }
            }
            if !viewModel.finishedTasks.isEmpty {
                Section("Finished") {
                    ForEach(viewModel.finishedTasks) { task in
                        row(for: task)
                    }
                    .onDelete { offsets in
                        delete(at: offsets, in: viewModel.finishedTasks)
                    }
                }
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        TaskRow(task: task)
            .contextMenu {
                Menu("Change priority") {
                    ForEach(Priority.allCases) { priority in
                        Button(priority.title) {
                            Task { await viewModel.setPriority(priority, for: task) }
                        }
                    }
                }
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(task) }
                }
            }
    }

    private func delete(at offsets: IndexSet, in tasks: [TaskItem]) {
        let targets = offsets.map { tasks[$0] }
        Task {
            for task in targets {
                await viewModel.delete(task)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { viewModel.clearError() }
                .font(.footnote.bold())
        }
        .foregroundStyle(.red)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("tasks.error")
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
                if let minutes = task.durationMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                }
                if !task.status.isActive {
                    Text(task.status.rawValue.capitalized)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                         durationMinutes: 10, createdBy: "me", order: 1)
            ]),
            ownerUid: "me"
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        TaskListView(repository: MockTaskRepository(), ownerUid: "me")
    }
}
