import Foundation

/// A recurring time window that starts a Lock automatically, such as 10pm–7am.
public struct Schedule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blockListID: UUID
    public var start: TimeOfDay
    /// If `end` is at or before `start`, the window runs past midnight into the next day.
    public var end: TimeOfDay
    /// The days a window may start on, as `Calendar` weekdays (1 is Sunday).
    public var weekdays: Set<Int>
    public var isEnabled: Bool

    public static let everyDay: Set<Int> = Set(1...7)

    public init(
        id: UUID = UUID(),
        name: String,
        blockListID: UUID,
        start: TimeOfDay,
        end: TimeOfDay,
        weekdays: Set<Int> = Schedule.everyDay,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.blockListID = blockListID
        self.start = start
        self.end = end
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    public var crossesMidnight: Bool { end <= start }

    /// Length of one window in minutes.
    public var durationMinutes: Int {
        let minutes = end.minutesSinceMidnight - start.minutesSinceMidnight
        return minutes > 0 ? minutes : minutes + 24 * 60
    }

    /// The window that contains `date`, if the Schedule is on at that moment.
    public func window(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isEnabled, !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        // A window that crosses midnight may have started yesterday.
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let windowStart = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
                  let windowEnd = calendar.date(byAdding: .minute, value: durationMinutes, to: windowStart)
            else { continue }
            if windowStart <= date, date < windowEnd {
                return DateInterval(start: windowStart, end: windowEnd)
            }
        }
        return nil
    }

    /// The start of the next window after `date`, looking up to a week ahead.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled, !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let windowStart = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
                  windowStart > date
            else { continue }
            return windowStart
        }
        return nil
    }

    /// Every minute of `other`'s windows is also inside this Schedule's windows.
    public func covers(_ other: Schedule) -> Bool {
        guard other.isEnabled else { return true }
        guard isEnabled, other.weekdays.isSubset(of: weekdays) else { return false }
        // Compare as minute ranges from this Schedule's start, so windows past midnight line up.
        let offset = (other.start.minutesSinceMidnight - start.minutesSinceMidnight + 24 * 60) % (24 * 60)
        return offset + other.durationMinutes <= durationMinutes
    }
}

extension TimeOfDay {
    /// The next moment at this time of day strictly after `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? date
        if candidate > date { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(24 * 60 * 60)
    }
}
