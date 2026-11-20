import Foundation

/// Formats the focus countdown for display and for VoiceOver.
enum CountdownFormatter {

    /// Clock-style text: `MM:SS`, or `H:MM:SS` from one hour up. Once time has
    /// run out it shows overtime with a leading "+" (e.g. `+02:15`).
    static func clockString(for remaining: TimeInterval) -> String {
        if remaining > 0 {
            // Round up so the display reads 00:01 until the moment time is up.
            return format(Int(remaining.rounded(.up)))
        }
        let overtime = Int((-remaining).rounded(.down))
        return overtime > 0 ? "+" + format(overtime) : format(0)
    }

    static func isOvertime(_ remaining: TimeInterval) -> Bool {
        remaining <= 0
    }

    /// Spoken form, e.g. "12 minutes, 30 seconds remaining". VoiceOver reads
    /// this instead of the ticking digits.
    static func spokenString(for remaining: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        if remaining > 0 {
            return (formatter.string(from: remaining.rounded(.up)) ?? "") + " remaining"
        }
        let overtime = (-remaining).rounded(.down)
        guard overtime > 0, let text = formatter.string(from: overtime) else {
            return "Time is up"
        }
        return "Time is up, \(text) over"
    }

    /// A time budget as short text, e.g. "25 min" or "1 hr, 30 min".
    static func allotmentString(for interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: interval) ?? ""
    }

    private static func format(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
