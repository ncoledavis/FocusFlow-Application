import SwiftUI

/// Root router (Task 2.10). Shows the auth flow when signed out and the main
/// app when signed in, reacting to session changes from the `SessionViewModel`.
struct RootView: View {
    @StateObject private var session: SessionViewModel
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
        _session = StateObject(wrappedValue: SessionViewModel(authService: authService))
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                HomeView()
                    .environmentObject(session)
            } else {
                AuthView(authService: authService)
            }
        }
        .animation(.default, value: session.isSignedIn)
    }
}

#Preview("Signed out") {
    RootView(authService: MockAuthService())
}

#Preview("Signed in") {
    RootView(authService: MockAuthService(
        startingUser: AppUser(id: "preview", email: "demo@focusflow.app")
    ))
}
