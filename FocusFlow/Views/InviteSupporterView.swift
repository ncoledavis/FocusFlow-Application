import SwiftUI

/// Sheet for inviting a supporter: choose what they can do, then get a code to
/// share.
struct InviteSupporterView: View {
    @ObservedObject var viewModel: SupportLinksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var permission: LinkPermission = .view
    @State private var didCopy = false

    /// The text shared with the code.
    static func shareMessage(for code: String) -> String {
        "I'd like you to be my supporter on FocusFlow. Open the Support tab, tap \"Enter an invite code\", "
            + "and enter: \(InviteCode.formatted(code))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let invite = viewModel.latestInvite {
                    shareSection(for: invite)
                } else {
                    chooseSection
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite a supporter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.latestInvite == nil {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.latestInvite != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            viewModel.clearError()
            viewModel.dismissLatestInvite()
        }
        .onDisappear { viewModel.dismissLatestInvite() }
    }

    // MARK: - Choose permission

    private var chooseSection: some View {
        Group {
            Section {
                Picker("What can they do?", selection: $permission) {
                    ForEach(LinkPermission.allCases) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(option.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("What can they do?")
            } footer: {
                Text("You can change this, or remove them, at any time.")
            }

            Section {
                Button {
                    Task { await viewModel.createInvite(permission: permission) }
                } label: {
                    HStack {
                        if viewModel.isWorking { ProgressView() }
                        Text("Create invite")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(viewModel.isWorking)
            }
        }
    }

    // MARK: - Share the code

    private func shareSection(for invite: SupporterLink) -> some View {
        Group {
            Section {
                VStack(spacing: 8) {
                    Text(InviteCode.formatted(invite.id))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Text(invite.permission.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            } footer: {
                Text("Send this code to your supporter. It works once. They enter it in the Support tab under \"Enter an invite code\".")
            }

            Section {
                ShareLink(item: Self.shareMessage(for: invite.id)) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button {
                    UIPasteboard.general.string = InviteCode.formatted(invite.id)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy code", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
}

#Preview {
    InviteSupporterView(
        viewModel: SupportLinksViewModel(
            repository: MockLinkRepository(),
            user: AppUser(id: "me", email: "me@example.com")
        )
    )
}
