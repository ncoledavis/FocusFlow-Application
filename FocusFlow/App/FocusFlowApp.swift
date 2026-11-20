import SwiftUI

@main
struct FocusFlowApp: App {

    private let authService: AuthService
    private let taskRepository: TaskRepository

    init() {
        FirebaseConfig.configureIfAvailable()
        // Use the live Firebase backend when configured; otherwise fall back to
        // in-memory mocks so the app still builds and runs end-to-end before
        // GoogleService-Info.plist is added.
        if FirebaseConfig.isConfigured {
            authService = FirebaseAuthService()
            taskRepository = FirestoreTaskRepository()
        } else {
            authService = MockAuthService()
            taskRepository = MockTaskRepository()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService, taskRepository: taskRepository)
        }
    }
}
