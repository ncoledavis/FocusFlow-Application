import SwiftUI

/// Combined login / sign-up screen. A single form that flips between modes,
/// covering Task 2.8 (login) and 2.9 (sign-up + navigation between them).
struct AuthView: View {
    @StateObject private var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(authService: authService))
    }

    var body: some View {
        VStack(spacing: 24) {
            header

            VStack(spacing: 16) {
                emailField
                passwordField
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                submitButton
            }

            modeToggle

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 480)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)
            Text("FocusFlow")
                .font(.largeTitle.bold())
            Text(viewModel.mode == .signIn ? "Welcome back." : "Create your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
    }

    private var emailField: some View {
        TextField("Email", text: $viewModel.email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
            .onSubmit { focusedField = .password }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var passwordField: some View {
        SecureField("Password", text: $viewModel.password)
            .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit { Task { await submit() } }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("auth.error")
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.primaryButtonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isFormValid || viewModel.isLoading)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            Text(viewModel.mode == .signIn ? "New here?" : "Already have an account?")
                .foregroundStyle(.secondary)
            Button(viewModel.mode == .signIn ? "Create an account" : "Sign in") {
                viewModel.toggleMode()
            }
        }
        .font(.footnote)
    }

    // MARK: - Actions

    private func submit() async {
        focusedField = nil
        await viewModel.submit()
    }
}

#Preview {
    AuthView(authService: MockAuthService())
}
