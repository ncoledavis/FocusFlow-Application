import Foundation
import Combine

/// Drives the login and sign-up forms: holds field state, validates input,
/// calls the `AuthService`, and surfaces errors for display.
@MainActor
final class AuthViewModel: ObservableObject {

    enum Mode {
        case signIn
        case signUp
    }

    @Published var mode: Mode = .signIn
    @Published var email: String = ""
    @Published var password: String = ""

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    /// Whether the current form passes basic client-side validation.
    var isFormValid: Bool {
        Self.isValidEmail(email) && password.count >= 6
    }

    var primaryButtonTitle: String {
        mode == .signIn ? "Sign In" : "Create Account"
    }

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
    }

    /// Submits the form for the active mode. Returns true on success.
    @discardableResult
    func submit() async -> Bool {
        errorMessage = nil

        guard Self.isValidEmail(email) else {
            errorMessage = AuthError.invalidEmail.errorDescription
            return false
        }
        guard password.count >= 6 else {
            errorMessage = AuthError.weakPassword.errorDescription
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                _ = try await authService.signIn(email: email, password: password)
            case .signUp:
                _ = try await authService.signUp(email: email, password: password)
            }
            return true
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Validation

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Simple, permissive check: something@something.tld
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
