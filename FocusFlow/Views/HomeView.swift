import SwiftUI

/// Placeholder signed-in landing screen. The task list and focus view replace
/// this in Tasks 3 and 4; for now it confirms sign-in worked and offers sign-out.
struct HomeView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checklist")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("You're signed in")
                    .font(.title2.bold())

                if let email = session.currentUser?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Your tasks will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding()
            .navigationTitle("FocusFlow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(SessionViewModel(
            authService: MockAuthService(
                startingUser: AppUser(id: "preview", email: "demo@focusflow.app")
            )
        ))
}
