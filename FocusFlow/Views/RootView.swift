import SwiftUI

/// Placeholder root view so the app launches. Replaced in Task 2 by a router
/// that switches between the auth flow and the main app based on session state.
struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)

            Text("FocusFlow")
                .font(.largeTitle.bold())

            Text("One task at a time.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
