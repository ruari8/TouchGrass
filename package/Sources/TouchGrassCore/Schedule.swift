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
    /// Set on a temporary copy of an edited Schedule's new window. It enforces the added time straight
    /// away while the edit as a whole waits for the Reset Time, and disappears when the edit applies.
    public var bridgesEditOf: UUID?

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
                  let window = window(startingOn: day, calendar: calendar)
            else { continue }
            if window.contains(date), date < window.end {
                return window
            }
        }
        return nil
    }

    /// The window starting on `day`, if the Schedule runs that weekday. The end is built from the
    /// local clock time, so a clock change overnight doesn't move it.
    private func window(startingOn day: Date, calendar: Calendar) -> DateInterval? {
        guard weekdays.contains(calendar.component(.weekday, from: day)),
              let endDay = calendar.date(byAdding: .day, value: crossesMidnight ? 1 : 0, to: day),
              let windowStart = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
              let windowEnd = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: endDay),
              windowStart < windowEnd
        else { return nil }
        return DateInterval(start: windowStart, end: windowEnd)
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

    /// Every minute of `other`'s windows is also inside this Schedule's windows, across the whole week.
    public func covers(_ other: Schedule) -> Bool {
        guard other.isEnabled, !other.weekdays.isEmpty else { return true }
        guard isEnabled else { return false }
        let mine = minutesOfWeek
        return other.minutesOfWeek.isSubset(of: mine)
    }

    /// Each window as minutes from the start of Sunday, wrapping Saturday night into Sunday morning.
    private var minutesOfWeek: Set<Int> {
        let week = 7 * 24 * 60
        var minutes = Set<Int>()
        for weekday in weekdays {
            let first = (weekday - 1) * 24 * 60 + start.minutesSinceMidnight
            for minute in first..<(first + durationMinutes) {
                minutes.insert(minute % week)
            }
        }
        return minutes
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
