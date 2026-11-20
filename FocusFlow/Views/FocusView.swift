import SwiftUI

/// The main screen: one task at a time, with a live countdown. Hosted in the
/// Focus tab.
struct FocusView: View {
    @StateObject private var viewModel: FocusViewModel
    private let onAddTask: () -> Void

    /// - Parameter onAddTask: Called from the empty state to send the user to
    ///   the task list.
    init(repository: TaskRepository, ownerUid: String, onAddTask: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: FocusViewModel(repository: repository, ownerUid: ownerUid)
        )
        self.onAddTask = onAddTask
    }

    var body: some View {
        content
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message, onDismiss: viewModel.clearError)
                }
            }
            .task { viewModel.start() }
    }

    @ViewBuilder
    private var content: some View {
        if let task = viewModel.currentTask {
            // Re-render every second so the countdown ticks.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                FocusCardView(
                    task: task,
                    remaining: viewModel.displayRemaining(asOf: context.date),
                    fraction: viewModel.remainingFraction(asOf: context.date),
                    upNextCount: viewModel.upNextCount,
                    isWorking: viewModel.isWorking,
                    onDone: { Task { await viewModel.markDone() } },
                    onSkip: { Task { await viewModel.skip() } }
                )
            }
        } else if viewModel.isLoading {
            ProgressView("Loading…")
        } else {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("No tasks waiting. Add one when you're ready.")
            } actions: {
                Button("Go to Tasks", action: onAddTask)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview("With tasks") {
    NavigationStack {
        FocusView(
            repository: MockTaskRepository(initialTasks: [
                TaskItem(id: "1", ownerUid: "me", title: "Write the project report",
                         priority: .high, durationMinutes: 25, createdBy: "me"),
                TaskItem(id: "2", ownerUid: "me", title: "Email advisor",
                         priority: .low, durationMinutes: 10, createdBy: "me", order: 1)
            ]),
            ownerUid: "me",
            onAddTask: {}
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        FocusView(repository: MockTaskRepository(), ownerUid: "me", onAddTask: {})
    }
}
