import Foundation
import Combine

/// Everything about the signed-in user's supporter links, from both sides:
/// the people who support them (and invites waiting to be accepted), and the
/// people they support.
@MainActor
final class SupportLinksViewModel: ObservableObject {

    /// Every link the user is part of, as last emitted by the repository.
    @Published private(set) var links: [SupporterLink] = []

    /// True until the first snapshot (or error) arrives.
    @Published private(set) var isLoading = true

    /// True while a change is being saved, so buttons can't double-fire.
    @Published private(set) var isWorking = false

    @Published var errorMessage: String?

    /// The invite that was just created, so its code can be shown and shared.
    @Published private(set) var latestInvite: SupporterLink?

    let user: AppUser

    private let repository: LinkRepository
    private var cancellable: AnyCancellable?

    init(repository: LinkRepository, user: AppUser) {
        self.repository = repository
        self.user = user
    }

    // MARK: - Derived lists

    /// People who support me.
    var mySupporters: [SupporterLink] {
        Self.sorted(links.filter { $0.status == .active && $0.ownerUid == user.id })
    }

    /// Invites I've sent that nobody has accepted yet.
    var pendingInvites: [SupporterLink] {
        Self.sorted(links.filter { $0.status == .pending && $0.ownerUid == user.id })
    }

    /// People whose task lists I help with.
    var supportedOwners: [SupporterLink] {
        Self.sorted(links.filter { $0.status == .active && $0.supporterUid == user.id })
    }

    /// The current version of a link, so a screen that's open can react when
    /// its permission changes or it's removed.
    func link(withId id: String) -> SupporterLink? {
        links.first { $0.id == id }
    }

    private static func sorted(_ links: [SupporterLink]) -> [SupporterLink] {
        links.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Subscription

    /// Starts listening to the repository. Safe to call more than once.
    func start() {
        guard cancellable == nil else { return }
        isLoading = true

        cancellable = repository.observeLinks(forUser: user.id)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        self.errorMessage = ErrorMessage.forRepository(error)
                    }
                    self.isLoading = false
                },
                receiveValue: { [weak self] links in
                    self?.links = links
                    self?.isLoading = false
                }
            )
    }

    // MARK: - Owner actions

    /// Creates an invite with the given permission and remembers it as
    /// `latestInvite`. Returns nil on failure.
    @discardableResult
    func createInvite(permission: LinkPermission) async -> SupporterLink? {
        var created: SupporterLink?
        let succeeded = await perform {
            created = try await self.repository.createInvite(
                ownerUid: self.user.id,
                ownerEmail: self.user.email,
                permission: permission
            )
        }
        if succeeded { latestInvite = created }
        return succeeded ? created : nil
    }

    func dismissLatestInvite() {
        latestInvite = nil
    }

    @discardableResult
    func updatePermission(of link: SupporterLink, to permission: LinkPermission) async -> Bool {
        await perform { try await self.repository.updatePermission(of: link, to: permission) }
    }

    /// Removes a supporter's access, or cancels a pending invite.
    @discardableResult
    func revoke(_ link: SupporterLink) async -> Bool {
        let succeeded = await perform { try await self.repository.revoke(link) }
        if succeeded, latestInvite?.id == link.id { latestInvite = nil }
        return succeeded
    }

    // MARK: - Supporter action

    /// Joins someone's list using the code they shared. Accepts the code as a
    /// person would type or paste it (any case, with or without the hyphen).
    @discardableResult
    func acceptInvite(code input: String) async -> Bool {
        let code = InviteCode.normalized(input)
        guard InviteCode.isValid(code) else {
            errorMessage = "Invite codes are 8 letters and numbers, like ABCD-EFGH."
            return false
        }
        return await perform {
            _ = try await self.repository.acceptInvite(
                code: code,
                supporterUid: self.user.id,
                supporterEmail: self.user.email
            )
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private func perform(_ work: () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await work()
            return true
        } catch {
            errorMessage = ErrorMessage.forRepository(error)
            return false
        }
    }
}
