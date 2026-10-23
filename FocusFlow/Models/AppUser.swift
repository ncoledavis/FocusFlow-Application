import Foundation

/// A user account. Mirrors `users/{uid}` in Firestore.
struct AppUser: Codable, Identifiable, Equatable {
    /// Firebase Auth UID. Serves as the document ID.
    var id: String
    var email: String
    var displayName: String?

    /// Whether this account currently acts as a supporter for someone else.
    var isSupporter: Bool

    /// Account creation timestamp.
    var createdAt: Date

    init(
        id: String,
        email: String,
        displayName: String? = nil,
        isSupporter: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isSupporter = isSupporter
        self.createdAt = createdAt
    }
}
