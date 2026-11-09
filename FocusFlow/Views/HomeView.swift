import SwiftUI

/// Signed-in landing screen: the user's live task list plus sign-out. The
/// one-at-a-time focus view replaces the list as the main screen in Task 4.
struct HomeView: View {
    @EnvironmentObject private var session: SessionViewModel

    let user: AppUser
    let taskRepository: TaskRepository

    var body: some View {
        NavigationStack {
            TaskListView(repository: taskRepository, ownerUid: user.id)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out", role: .destructive) {
                            session.signOut()
                        }
                    }
                }
        }
    }
}

#Preview {
    let user = AppUser(id: "preview", email: "demo@focusflow.app")
    return HomeView(user: user, taskRepository: MockTaskRepository())
        .environmentObject(SessionViewModel(authService: MockAuthService(startingUser: user)))
}
