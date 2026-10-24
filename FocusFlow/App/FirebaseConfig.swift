import Foundation
import FirebaseCore

/// Centralizes Firebase startup.
///
/// Firebase is configured only when a `GoogleService-Info.plist` is bundled
/// (see Task 2.3). Until you add that file from the Firebase console, the app
/// still builds and launches — it simply runs without a live backend, which is
/// why the app falls back to a mock `AuthService` in that case.
enum FirebaseConfig {

    /// Whether a `GoogleService-Info.plist` is present in the app bundle.
    static var isConfigured: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Configures Firebase if the plist is present. Safe to call once at launch.
    static func configureIfAvailable() {
        guard isConfigured else {
            #if DEBUG
            print("[FirebaseConfig] GoogleService-Info.plist not found — running without Firebase. "
                  + "Add it from the Firebase console to enable the live backend.")
            #endif
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #if DEBUG
        print("[FirebaseConfig] Firebase configured ✓ — using the live backend.")
        #endif
    }
}
