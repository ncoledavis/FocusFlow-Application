import SwiftUI

/// The single-task card: what to do, how long you have, a live countdown, and
/// big Done / Skip buttons. Purely presentational; `FocusView` supplies values.
struct FocusCardView: View {
    let task: TaskItem
    let remaining: TimeInterval?
    let fraction: Double?
    let upNextCount: Int
    let isWorking: Bool
    let notificationsOff: Bool
    let onDone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView { content }
            .safeAreaInset(edge: .bottom) { actionButtons }
    }

    /// The card's scrolling content, separate from the scroll container.
    var content: some View {
        VStack(spacing: 24) {
            header
            CountdownRingView(remaining: remaining, fraction: fraction)
            timeDetails
            if upNextCount > 0 {
                Text(upNextCount == 1 ? "1 more task up next" : "\(upNextCount) more tasks up next")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if notificationsOff {
                notificationsOffNote
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Label(task.priority.title, systemImage: "flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(priorityColor)

            Text(task.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            if let notes = task.notes {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var timeDetails: some View {
        VStack(spacing: 6) {
            if let allotted = task.allottedInterval {
                Label("\(CountdownFormatter.allotmentString(for: allotted)) given", systemImage: "hourglass")
            }
            if let finish = task.targetFinishAt {
                Label("Finish by \(finish.formatted(date: .omitted, time: .shortened))", systemImage: "flag.checkered")
            } else {
                Label("Clock starts when you begin", systemImage: "play.circle")
            }
            if task.scheduleType == .fixed, let start = task.startAt {
                Label("Scheduled for \(start.formatted(date: .omitted, time: .shortened))", systemImage: "calendar.clock")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    /// Shown when notifications are denied: explains the fallback and links to
    /// Settings.
    private var notificationsOffNote: some View {
        VStack(spacing: 4) {
            Label("Notifications are off. You'll only be alerted while the app is open.", systemImage: "bell.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onSkip) {
                Label("Skip", systemImage: "forward.end")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .disabled(isWorking)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

#Preview("Duration task") {
    FocusCardView(
        task: TaskItem(
            id: "1", ownerUid: "me", title: "Write the project report",
            notes: "Start with the results section.", priority: .high,
            durationMinutes: 25, startAt: Date().addingTimeInterval(-600),
            status: .current, createdBy: "me"
        ),
        remaining: 900,
        fraction: 0.6,
        upNextCount: 3,
        isWorking: false,
        notificationsOff: true,
        onDone: {},
        onSkip: {}
    )
}
