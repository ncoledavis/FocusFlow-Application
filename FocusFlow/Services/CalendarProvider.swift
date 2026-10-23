import Foundation

/// A source of calendar events. Implemented by EventKit, Google, and Mock
/// adapters (Task 7). Read-only for now; designed for future two-way sync.
protocol CalendarProvider {
    /// Human-facing provider name (e.g. "Apple", "Google", "Demo").
    var displayName: String { get }

    /// Request read access from the user. Returns whether access was granted.
    func requestAccess() async throws -> Bool

    /// Fetch events overlapping the given date interval.
    func fetchEvents(in interval: DateInterval) async throws -> [CalendarEvent]
}
