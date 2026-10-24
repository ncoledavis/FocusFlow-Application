import Foundation
import Combine

/// Tracks the signed-in session for the whole app. The root router observes
/// `currentUser` to decide between the auth flow and the main app.
@MainActor
final class SessionViewModel: ObservableObject {

    @Published private(set) var currentUser: AppUser?

    let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService) {
        self.authService = authService
        self.currentUser = authService.currentUser

        authService.currentUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }

    var isSignedIn: Bool { currentUser != nil }

    func signOut() {
        try? authService.signOut()
    }
}
