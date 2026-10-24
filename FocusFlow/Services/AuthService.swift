import Foundation
import Combine

/// Domain-level authentication errors, decoupled from any Firebase types so
/// view models and tests can reason about failures uniformly.
enum AuthError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case wrongPassword
    case userNotFound
    case networkError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "That email address doesn't look valid."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .emailAlreadyInUse:
            return "An account already exists for that email."
        case .wrongPassword:
            return "Incorrect password. Try again."
        case .userNotFound:
            return "No account found for that email."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .unknown(let message):
            return message
        }
    }
}

/// Authentication boundary. Implemented by `FirebaseAuthService` in production
/// and `MockAuthService` in tests.
protocol AuthService {
    /// Emits the current signed-in user, or nil when signed out.
    var currentUserPublisher: AnyPublisher<AppUser?, Never> { get }

    /// The current user synchronously, if any.
    var currentUser: AppUser? { get }

    func signUp(email: String, password: String) async throws -> AppUser
    func signIn(email: String, password: String) async throws -> AppUser
    func signOut() throws
}
