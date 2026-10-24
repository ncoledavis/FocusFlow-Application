import XCTest
import Combine
@testable import FocusFlow

@MainActor
final class AuthViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Validation

    func testEmailValidation() {
        XCTAssertTrue(AuthViewModel.isValidEmail("a@b.com"))
        XCTAssertTrue(AuthViewModel.isValidEmail("user.name@example.co.uk"))
        XCTAssertFalse(AuthViewModel.isValidEmail(""))
        XCTAssertFalse(AuthViewModel.isValidEmail("no-at-sign"))
        XCTAssertFalse(AuthViewModel.isValidEmail("missing@tld"))
        XCTAssertFalse(AuthViewModel.isValidEmail("spaces @b.com"))
    }

    func testFormValidityRequiresEmailAndPasswordLength() {
        let viewModel = AuthViewModel(authService: MockAuthService())
        XCTAssertFalse(viewModel.isFormValid)

        viewModel.email = "user@focusflow.app"
        viewModel.password = "123"
        XCTAssertFalse(viewModel.isFormValid, "Short password should be invalid")

        viewModel.password = "123456"
        XCTAssertTrue(viewModel.isFormValid)
    }

    // MARK: - Sign up / sign in success

    func testSignUpSuccessSignsUserIn() async {
        let service = MockAuthService()
        let viewModel = AuthViewModel(authService: service)
        viewModel.mode = .signUp
        viewModel.email = "new@focusflow.app"
        viewModel.password = "secret123"

        let succeeded = await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.currentUser?.email, "new@focusflow.app")
    }

    func testSignInSuccess() async {
        let service = MockAuthService()
        // Seed an account via sign-up, then sign out.
        _ = try? await service.signUp(email: "existing@focusflow.app", password: "secret123")
        try? service.signOut()

        let viewModel = AuthViewModel(authService: service)
        viewModel.mode = .signIn
        viewModel.email = "existing@focusflow.app"
        viewModel.password = "secret123"

        let succeeded = await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(service.currentUser?.email, "existing@focusflow.app")
    }

    // MARK: - Bad credentials

    func testSignInWrongPasswordSurfacesError() async {
        let service = MockAuthService()
        _ = try? await service.signUp(email: "user@focusflow.app", password: "correct123")
        try? service.signOut()

        let viewModel = AuthViewModel(authService: service)
        viewModel.mode = .signIn
        viewModel.email = "user@focusflow.app"
        viewModel.password = "wrongpass"

        let succeeded = await viewModel.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, AuthError.wrongPassword.errorDescription)
        XCTAssertNil(service.currentUser)
    }

    func testSignInUnknownUserSurfacesError() async {
        let service = MockAuthService()
        let viewModel = AuthViewModel(authService: service)
        viewModel.mode = .signIn
        viewModel.email = "ghost@focusflow.app"
        viewModel.password = "secret123"

        let succeeded = await viewModel.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, AuthError.userNotFound.errorDescription)
    }

    func testSignUpDuplicateEmailSurfacesError() async {
        let service = MockAuthService()
        _ = try? await service.signUp(email: "dupe@focusflow.app", password: "secret123")

        let viewModel = AuthViewModel(authService: service)
        viewModel.mode = .signUp
        viewModel.email = "dupe@focusflow.app"
        viewModel.password = "secret123"

        let succeeded = await viewModel.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, AuthError.emailAlreadyInUse.errorDescription)
    }

    func testInvalidEmailBlockedBeforeServiceCall() async {
        let service = MockAuthService()
        let viewModel = AuthViewModel(authService: service)
        viewModel.email = "not-an-email"
        viewModel.password = "secret123"

        let succeeded = await viewModel.submit()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, AuthError.invalidEmail.errorDescription)
    }

    // MARK: - Sign out

    func testSignOutClearsSession() async throws {
        let service = MockAuthService()
        _ = try await service.signUp(email: "user@focusflow.app", password: "secret123")
        XCTAssertNotNil(service.currentUser)

        try service.signOut()
        XCTAssertNil(service.currentUser)
    }

    // MARK: - Session view model

    func testSessionViewModelTracksAuthState() async throws {
        let service = MockAuthService()
        let session = SessionViewModel(authService: service)
        XCTAssertFalse(session.isSignedIn)

        _ = try await service.signUp(email: "user@focusflow.app", password: "secret123")
        try await waitForMainQueue()
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.currentUser?.email, "user@focusflow.app")

        session.signOut()
        try await waitForMainQueue()
        XCTAssertFalse(session.isSignedIn)
    }

    /// Lets the main run loop turn so Combine sinks using `.receive(on:.main)`
    /// deliver their values before assertions run.
    private func waitForMainQueue() async throws {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testToggleModeClearsError() async {
        let service = MockAuthService()
        let viewModel = AuthViewModel(authService: service)
        viewModel.email = "bad"
        viewModel.password = "secret123"
        _ = await viewModel.submit()
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.toggleMode()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.mode, .signUp)
    }
}
