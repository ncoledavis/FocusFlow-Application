import Foundation
import Combine

/// Authentication boundary. Concrete implementation (FirebaseAuthService)
/// arrives in Task 2; a mock implementation backs view-model tests.
protocol AuthService {
    /// Emits the current signed-in user, or nil when signed out.
    var currentUserPublisher: AnyPublisher<AppUser?, Never> { get }

    /// The current user synchronously, if any.
    var currentUser: AppUser? { get }

    func signUp(email: String, password: String) async throws -> AppUser
    func signIn(email: String, password: String) async throws -> AppUser
    func signOut() throws
}
