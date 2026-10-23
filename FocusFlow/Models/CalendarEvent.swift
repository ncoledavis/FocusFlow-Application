import Foundation

/// A calendar event, normalized across providers (EventKit, Google, Mock).
/// The shared shape that the UI and timeline logic consume.
struct CalendarEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var startAt: Date
    var endAt: Date
    var isAllDay: Bool

    /// Provider-defined calendar/source name, for display or filtering.
    var calendarName: String?

    init(
        id: String,
        title: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        calendarName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.calendarName = calendarName
    }
}
