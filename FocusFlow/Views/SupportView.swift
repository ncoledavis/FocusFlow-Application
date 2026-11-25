import SwiftUI

/// The Support tab. Two sides of the same feature: the people who support me
/// (invite them, change what they can do, remove them), and the people whose
/// lists I help with (join with a code, open their list).
struct SupportView: View {
    @ObservedObject var viewModel: SupportLinksViewModel
    let taskRepository: TaskRepository

    @State private var isInviting = false
    @State private var isJoining = false
    @State private var linkToRemove: SupporterLink?

    var body: some View {
        List {
            mySupportersSection
            pendingInvitesSection
            peopleISupportSection
        }
        .navigationTitle("Support")
        .sheet(isPresented: $isInviting) { InviteSupporterView(viewModel: viewModel) }
        .sheet(isPresented: $isJoining) { JoinWithCodeView(viewModel: viewModel) }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { linkToRemove != nil }, set: { if !$0 { linkToRemove = nil } }),
            titleVisibility: .visible,
            presenting: linkToRemove
        ) { link in
            Button(link.status == .pending ? "Cancel invite" : "Remove", role: .destructive) {
                Task { await viewModel.revoke(link) }
            }
        } message: { link in
            Text(link.status == .pending
                 ? "The code will stop working."
                 : "They'll immediately lose access to your tasks.")
        }
        .safeAreaInset(edge: .bottom) {
            if let message = viewModel.errorMessage {
                ErrorBanner(message: message, onDismiss: viewModel.clearError)
            }
        }
    }

    private var removalTitle: String {
        guard let link = linkToRemove else { return "" }
        return link.status == .pending ? "Cancel this invite?" : "Remove \(link.supporterLabel)?"
    }

    // MARK: - People who support me

    private var mySupportersSection: some View {
        Section {
            ForEach(viewModel.mySupporters) { link in
                supporterRow(link)
            }
            Button {
                isInviting = true
            } label: {
                Label("Invite a supporter", systemImage: "person.badge.plus")
            }
        } header: {
            Text("People who support me")
        } footer: {
            if viewModel.mySupporters.isEmpty && viewModel.pendingInvites.isEmpty {
                Text("A supporter is someone you trust who can see your tasks and, if you let them, add tasks or change their priority.")
            }
        }
    }

    private func supporterRow(_ link: SupporterLink) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.supporterLabel)
                    .font(.headline)
                Text(link.permission.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            permissionMenu(for: link, removeTitle: "Remove supporter")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pending invites

    @ViewBuilder
    private var pendingInvitesSection: some View {
        if !viewModel.pendingInvites.isEmpty {
            Section {
                ForEach(viewModel.pendingInvites) { invite in
                    inviteRow(invite)
                }
            } header: {
                Text("Waiting to be accepted")
            } footer: {
                Text("Each code works once. Share it only with the person you're inviting.")
            }
        }
    }

    private func inviteRow(_ invite: SupporterLink) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(InviteCode.formatted(invite.id))
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                Text(invite.permission.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(item: InviteSupporterView.shareMessage(for: invite.id)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share invite")
            .buttonStyle(.borderless)
            permissionMenu(for: invite, removeTitle: "Cancel invite")
        }
    }

    /// The "…" menu: pick a permission, or remove.
    private func permissionMenu(for link: SupporterLink, removeTitle: String) -> some View {
        Menu {
            Picker("Permission", selection: Binding(
                get: { link.permission },
                set: { newValue in
                    Task { await viewModel.updatePermission(of: link, to: newValue) }
                }
            )) {
                ForEach(LinkPermission.allCases) { permission in
                    Text(permission.title).tag(permission)
                }
            }
            Divider()
            Button(removeTitle, role: .destructive) {
                linkToRemove = link
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(viewModel.isWorking)
        .accessibilityLabel("Options for \(link.status == .pending ? "invite" : link.supporterLabel)")
    }

    // MARK: - People I support

    private var peopleISupportSection: some View {
        Section {
            ForEach(viewModel.supportedOwners) { link in
                NavigationLink {
                    SupportedOwnerTasksView(
                        viewModel: viewModel,
                        linkId: link.id,
                        taskRepository: taskRepository
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.ownerLabel)
                            .font(.headline)
                        Text(link.permission.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                isJoining = true
            } label: {
                Label("Enter an invite code", systemImage: "key")
            }
        } header: {
            Text("People I support")
        } footer: {
            if viewModel.supportedOwners.isEmpty {
                Text("Someone you want to help can send you a code. Enter it here to see their tasks.")
            }
        }
    }
}

#Preview {
    let user = AppUser(id: "me", email: "me@example.com")
    let repository = MockLinkRepository()
    let viewModel = SupportLinksViewModel(repository: repository, user: user)
    viewModel.start()
    return NavigationStack {
        SupportView(viewModel: viewModel, taskRepository: MockTaskRepository())
    }
}
