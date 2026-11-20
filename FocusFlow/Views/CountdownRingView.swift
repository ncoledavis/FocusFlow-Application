import SwiftUI

/// Clock-style countdown: a ring that drains as time runs out, with the time
/// left in the middle. When time is up the ring fills red and the caption says
/// so, so the state doesn't depend on color alone.
struct CountdownRingView: View {
    /// Seconds left. Nil shows a placeholder.
    let remaining: TimeInterval?

    /// Fraction of the allotment still left, 0...1.
    let fraction: Double?

    private let lineWidth: CGFloat = 18

    private var isOvertime: Bool {
        remaining.map(CountdownFormatter.isOvertime) ?? false
    }

    private var ringColor: Color {
        isOvertime ? .red : .accentColor
    }

    private var timeText: String {
        remaining.map(CountdownFormatter.clockString) ?? "--:--"
    }

    private var caption: String {
        isOvertime ? "Time's up" : "left"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: isOvertime ? 1 : (fraction ?? 0))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(timeText)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(isOvertime ? Color.red : Color.primary)
                Text(caption)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(36)
        }
        .frame(width: 280, height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(remaining.map(CountdownFormatter.spokenString) ?? "Not started")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Running") {
    CountdownRingView(remaining: 754, fraction: 0.5)
}

#Preview("Time's up") {
    CountdownRingView(remaining: -135, fraction: 0)
}
