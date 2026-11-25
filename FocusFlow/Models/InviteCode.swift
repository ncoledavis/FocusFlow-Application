import Foundation

/// The short code an owner shares so a supporter can join.
///
/// Eight characters from a 31-character alphabet (no `0 O 1 I L`, which are easy
/// to misread), about 40 bits of randomness. The code is also the Firestore
/// document ID of the invite, so possession of it is the only thing that lets
/// someone accept; it's consumed when used.
enum InviteCode {

    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 8

    /// A new random code from the system's secure random number generator.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<length).map { _ in
            alphabet.randomElement(using: &generator) ?? alphabet[0]
        }
        return String(characters)
    }

    /// Cleans up what a person typed or pasted: uppercases it and drops spaces,
    /// hyphens, and anything else that isn't a letter or digit.
    static func normalized(_ input: String) -> String {
        String(input.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Whether a normalized code has the right length and only valid characters.
    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }

    /// Display form, e.g. `ABCD-EFGH`.
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(length / 2))-\(code.suffix(length / 2))"
    }
}
