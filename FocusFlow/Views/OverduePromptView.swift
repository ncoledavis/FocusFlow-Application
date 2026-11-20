import SwiftUI

/// "Still working on this?" prompt shown when a task's time runs out. The
/// three choices cover everything the user can do, so the sheet can't be
/// swiped away without picking one.
struct OverduePromptView: View {
    let taskTitle: String
    let extensionOptions: [Int]
    let isWorking: Bool
    let onAddTime: (Int) -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                addTimeSection
                actions
            }
            .padding(24)
        }
        .disabled(isWorking)
        .interactiveDismissDisabled()
        // Tall enough that Mark done and Skip are visible without scrolling.
        .presentationDetents([.fraction(0.75), .large])
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "alarm.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Time's up")
                .font(.title.bold())
            Text(taskTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Still working on this?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var addTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add more time (minutes)")
                .font(.subheadline.weight(.semibold))
            // Four options fit one row at normal text size and wrap at larger sizes.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(extensionOptions, id: \.self) { minutes in
                    Button {
                        onAddTime(minutes)
                    } label: {
                        Text("+\(minutes)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Add \(minutes) minutes")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onDone) {
                Label("Mark done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onSkip) {
                Label("Skip", systemImage: "forward.end")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}

#Preview {
    OverduePromptView(
        taskTitle: "Write the project report",
        extensionOptions: FocusViewModel.extensionOptions,
        isWorking: false,
        onAddTime: { _ in },
        onDone: {},
        onSkip: {}
    )
}
