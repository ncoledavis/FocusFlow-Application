import SwiftUI

/// Signed-in home: a Focus tab (one task at a time) and a Tasks tab (the full
/// list and add form). Owns the focus view model so it keeps running, and can
/// present the "time's up" prompt, whichever tab is showing.
struct HomeView: View {
    private enum Tab {
        case focus
        case tasks
    }

    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var focusViewModel: FocusViewModel
    @State private var selection: Tab = .focus

    let user: AppUser
    let taskRepository: TaskRepository

    init(user: AppUser, taskRepository: TaskRepository, notificationService: NotificationService) {
        self.user = user
        self.taskRepository = taskRepository
        _focusViewModel = StateObject(
            wrappedValue: FocusViewModel(
                repository: taskRepository,
                ownerUid: user.id,
                notificationService: notificationService
            )
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                FocusView(viewModel: focusViewModel, onAddTask: { selection = .tasks })
                    .toolbar { signOutToolbar }
            }
            .tabItem { Label("Focus", systemImage: "scope") }
            .tag(Tab.focus)

            NavigationStack {
                TaskListView(repository: taskRepository, ownerUid: user.id)
                    .toolbar { signOutToolbar }
            }
            .tabItem { Label("Tasks", systemImage: "list.bullet") }
            .tag(Tab.tasks)
        }
        .task { focusViewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            // Picks up notifications being turned on or off in Settings.
            if phase == .active { focusViewModel.refreshNotificationPermission() }
        }
        .onChange(of: focusViewModel.isOverdue) { _, overdue in
            // Show the task the prompt is about.
            if overdue { selection = .focus }
        }
        .sheet(isPresented: overduePromptBinding) { overduePrompt }
    }

    // MARK: - Overdue prompt

    /// The prompt is driven by view-model state, and it can't be swiped away,
    /// so there's nothing to write back.
    private var overduePromptBinding: Binding<Bool> {
        Binding(get: { focusViewModel.isOverdue }, set: { _ in })
    }

    private var overduePrompt: some View {
        OverduePromptView(
            taskTitle: focusViewModel.currentTask?.title ?? "",
            extensionOptions: FocusViewModel.extensionOptions,
            isWorking: focusViewModel.isWorking,
            onAddTime: { minutes in Task { await focusViewModel.addMoreTime(minutes: minutes) } },
            onDone: { Task { await focusViewModel.markDone() } },
            onSkip: { Task { await focusViewModel.skip() } }
        )
    }

    @ToolbarContentBuilder
    private var signOutToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Sign Out", role: .destructive) {
                session.signOut()
            }
        }
    }
}

#Preview {
    let user = AppUser(id: "preview", email: "demo@focusflow.app")
    return HomeView(
        user: user,
        taskRepository: MockTaskRepository(),
        notificationService: MockNotificationService()
    )
    .environmentObject(SessionViewModel(authService: MockAuthService(startingUser: user)))
}
