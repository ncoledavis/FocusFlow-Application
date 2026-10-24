import SwiftUI

@main
struct FocusFlowApp: App {

    private let authService: AuthService

    init() {
        FirebaseConfig.configureIfAvailable()
        // Use the live Firebase backend when configured; otherwise fall back to
        // an in-memory mock so the app still builds and runs end-to-end before
        // GoogleService-Info.plist is added.
        if FirebaseConfig.isConfigured {
            authService = FirebaseAuthService()
        } else {
            authService = MockAuthService()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService)
        }
    }
}
