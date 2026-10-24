import Foundation
import Combine
import FirebaseAuth

/// `AuthService` backed by Firebase Authentication (email/password).
///
/// Translates Firebase's `User` into our `AppUser` and `AuthErrorCode` into our
/// domain `AuthError`, so the rest of the app never imports FirebaseAuth.
final class FirebaseAuthService: AuthService {

    private let auth: Auth
    private let subject: CurrentValueSubject<AppUser?, Never>
    private var handle: AuthStateDidChangeListenerHandle?

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
        self.subject = CurrentValueSubject(FirebaseAuthService.mapUser(auth.currentUser))

        // Keep the publisher in sync with Firebase's session, including
        // restoration on relaunch.
        handle = auth.addStateDidChangeListener { [weak self] _, user in
            self?.subject.send(FirebaseAuthService.mapUser(user))
        }
    }

    deinit {
        if let handle {
            auth.removeStateDidChangeListener(handle)
        }
    }

    var currentUserPublisher: AnyPublisher<AppUser?, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentUser: AppUser? {
        subject.value
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            return FirebaseAuthService.mapUser(result.user) ?? Self.fallbackUser(result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            return FirebaseAuthService.mapUser(result.user) ?? Self.fallbackUser(result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signOut() throws {
        do {
            try auth.signOut()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Mapping

    private static func mapUser(_ user: User?) -> AppUser? {
        guard let user, let email = user.email else { return nil }
        return AppUser(
            id: user.uid,
            email: email,
            displayName: user.displayName,
            createdAt: user.metadata.creationDate ?? Date()
        )
    }

    /// Used only in the unlikely case a signed-in Firebase user has no email.
    private static func fallbackUser(_ user: User) -> AppUser {
        AppUser(
            id: user.uid,
            email: user.email ?? "",
            displayName: user.displayName,
            createdAt: user.metadata.creationDate ?? Date()
        )
    }

    private static func mapError(_ error: Error) -> AuthError {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail:
            return .invalidEmail
        case .weakPassword:
            return .weakPassword
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .wrongPassword, .invalidCredential:
            return .wrongPassword
        case .userNotFound:
            return .userNotFound
        case .networkError:
            return .networkError
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
