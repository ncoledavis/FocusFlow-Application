import Foundation
import Combine

/// In-memory `AuthService` for previews and tests. Simulates an account store
/// without touching the network or Firebase.
final class MockAuthService: AuthService {

    private struct Account {
        let user: AppUser
        let password: String
    }

    private var accounts: [String: Account] = [:]
    private let subject: CurrentValueSubject<AppUser?, Never>

    /// When set, the next auth call throws this error instead of succeeding.
    /// Handy for exercising error paths in tests.
    var nextError: AuthError?

    init(startingUser: AppUser? = nil) {
        subject = CurrentValueSubject(startingUser)
        if let startingUser {
            accounts[startingUser.email.lowercased()] = Account(user: startingUser, password: "")
        }
    }

    var currentUserPublisher: AnyPublisher<AppUser?, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentUser: AppUser? { subject.value }

    func signUp(email: String, password: String) async throws -> AppUser {
        if let nextError { self.nextError = nil; throw nextError }

        let key = email.lowercased()
        guard accounts[key] == nil else { throw AuthError.emailAlreadyInUse }
        guard password.count >= 6 else { throw AuthError.weakPassword }

        let user = AppUser(id: UUID().uuidString, email: email)
        accounts[key] = Account(user: user, password: password)
        subject.send(user)
        return user
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        if let nextError { self.nextError = nil; throw nextError }

        let key = email.lowercased()
        guard let account = accounts[key] else { throw AuthError.userNotFound }
        guard account.password == password else { throw AuthError.wrongPassword }

        subject.send(account.user)
        return account.user
    }

    func signOut() throws {
        if let nextError { self.nextError = nil; throw nextError }
        subject.send(nil)
    }
}
