import SwiftUI

/// Sheet where a supporter enters the invite code they were given (6.6).
struct JoinWithCodeView: View {
    @ObservedObject var viewModel: SupportLinksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""

    private var canJoin: Bool {
        InviteCode.isValid(InviteCode.normalized(code)) && !viewModel.isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-EFGH", text: $code)
                        .font(.system(.title2, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .onSubmit(join)
                } header: {
                    Text("Invite code")
                } footer: {
                    Text("Ask the person you want to help for the code from their Support tab.")
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("join.error")
                    }
                }
            }
            .navigationTitle("Join with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", action: join)
                        .disabled(!canJoin)
                }
            }
        }
        .onAppear { viewModel.clearError() }
    }

    private func join() {
        guard canJoin else { return }
        Task {
            if await viewModel.acceptInvite(code: code) {
                dismiss()
            }
        }
    }
}

#Preview {
    JoinWithCodeView(
        viewModel: SupportLinksViewModel(
            repository: MockLinkRepository(),
            user: AppUser(id: "me", email: "me@example.com")
        )
    )
}
