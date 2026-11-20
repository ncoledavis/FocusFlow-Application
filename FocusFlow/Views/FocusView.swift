import SwiftUI

/// The main screen: one task at a time, with a live countdown. Hosted in the
/// Focus tab. The view model is owned by `HomeView`, which also starts it and
/// presents the "time's up" prompt, so both work from either tab.
struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel

    /// Called from the empty state to send the user to the task list.
    let onAddTask: () -> Void

    var body: some View {
        content
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message, onDismiss: viewModel.clearError)
                }
            }
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
                    notificationsOff: viewModel.notificationPermission == .denied,
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
    let viewModel = FocusViewModel(
        repository: MockTaskRepository(initialTasks: [
            TaskItem(id: "1", ownerUid: "me", title: "Write the project report",
                     priority: .high, durationMinutes: 25, createdBy: "me"),
            TaskItem(id: "2", ownerUid: "me", title: "Email advisor",
                     priority: .low, durationMinutes: 10, createdBy: "me", order: 1)
        ]),
        ownerUid: "me",
        notificationService: MockNotificationService()
    )
    viewModel.start()
    return NavigationStack {
        FocusView(viewModel: viewModel, onAddTask: {})
    }
}

#Preview("Empty") {
    let viewModel = FocusViewModel(
        repository: MockTaskRepository(),
        ownerUid: "me",
        notificationService: MockNotificationService()
    )
    viewModel.start()
    return NavigationStack {
        FocusView(viewModel: viewModel, onAddTask: {})
    }
}
