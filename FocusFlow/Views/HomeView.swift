import SwiftUI

/// Signed-in home: a Focus tab (one task at a time) and a Tasks tab (the full
/// list and add form).
struct HomeView: View {
    private enum Tab {
        case focus
        case tasks
    }

    @EnvironmentObject private var session: SessionViewModel
    @State private var selection: Tab = .focus

    let user: AppUser
    let taskRepository: TaskRepository

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                FocusView(
                    repository: taskRepository,
                    ownerUid: user.id,
                    onAddTask: { selection = .tasks }
                )
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
    return HomeView(user: user, taskRepository: MockTaskRepository())
        .environmentObject(SessionViewModel(authService: MockAuthService(startingUser: user)))
}
