import SwiftUI

/// Root router (Task 2.10). Shows the auth flow when signed out and the main
/// app when signed in, reacting to session changes from the `SessionViewModel`.
struct RootView: View {
    @StateObject private var session: SessionViewModel
    private let authService: AuthService
    private let taskRepository: TaskRepository
    private let notificationService: NotificationService

    init(authService: AuthService, taskRepository: TaskRepository, notificationService: NotificationService) {
        self.authService = authService
        self.taskRepository = taskRepository
        self.notificationService = notificationService
        _session = StateObject(wrappedValue: SessionViewModel(authService: authService))
    }

    var body: some View {
        Group {
            if let user = session.currentUser {
                HomeView(user: user, taskRepository: taskRepository, notificationService: notificationService)
                    .id(user.id)
                    .environmentObject(session)
            } else {
                AuthView(authService: authService)
            }
        }
        .animation(.default, value: session.isSignedIn)
    }
}

#Preview("Signed out") {
    RootView(
        authService: MockAuthService(),
        taskRepository: MockTaskRepository(),
        notificationService: MockNotificationService()
    )
}

#Preview("Signed in") {
    RootView(
        authService: MockAuthService(
            startingUser: AppUser(id: "preview", email: "demo@focusflow.app")
        ),
        taskRepository: MockTaskRepository(),
        notificationService: MockNotificationService()
    )
}
