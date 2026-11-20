import Foundation

/// Turns repository errors into messages suitable for the UI.
enum ErrorMessage {

    /// Firestore's "permission denied" gets an actionable hint; everything else
    /// uses the error's own description.
    static func forRepository(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "FIRFirestoreErrorDomain", nsError.code == 7 {
            return "Permission denied. Check that your Firestore security rules allow access to your tasks."
        }
        return error.localizedDescription
    }
}
