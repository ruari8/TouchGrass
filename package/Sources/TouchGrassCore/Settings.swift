import Foundation

/// A time of day, such as the Reset Time or the start of a Schedule.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public static let midnight = TimeOfDay(hour: 0)

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// The overall style chosen at setup. Each setting can then be changed on its own.
public enum Style: String, Codable, CaseIterable, Sendable {
    case strict
    case flexible
}

public struct Settings: Codable, Hashable, Sendable {
    /// Flexible: a Manual Lock can be given a duration. Strict: it lasts until Touch Grass.
    public var manualLocksCanHaveDuration: Bool
    /// Strict: Touch Grass earns a Break from Schedule and Budget Locks. Flexible: it ends them.
    public var touchGrassGivesBreak: Bool
    public var breakMinutes: Int
    /// Strict: loosening a setting only takes effect after the next Reset Time.
    public var looseningWaitsUntilTomorrow: Bool
    public var resetTime: TimeOfDay
    /// The Block List a Manual Lock uses unless another is chosen.
    public var defaultBlockListID: UUID?

    public init(
        manualLocksCanHaveDuration: Bool,
        touchGrassGivesBreak: Bool,
        breakMinutes: Int = 15,
        looseningWaitsUntilTomorrow: Bool,
        resetTime: TimeOfDay = .midnight,
        defaultBlockListID: UUID? = nil
    ) {
        self.manualLocksCanHaveDuration = manualLocksCanHaveDuration
        self.touchGrassGivesBreak = touchGrassGivesBreak
        self.breakMinutes = breakMinutes
        self.looseningWaitsUntilTomorrow = looseningWaitsUntilTomorrow
        self.resetTime = resetTime
        self.defaultBlockListID = defaultBlockListID
    }

    public static let breakMinuteOptions = [15, 30, 60]

    public static func preset(_ style: Style) -> Settings {
        switch style {
        case .strict:
            Settings(manualLocksCanHaveDuration: false, touchGrassGivesBreak: true, looseningWaitsUntilTomorrow: true)
        case .flexible:
            Settings(manualLocksCanHaveDuration: true, touchGrassGivesBreak: false, looseningWaitsUntilTomorrow: false)
        }
    }

    /// Replaces the style-controlled settings, keeping the Reset Time, Break length and default Block List.
    public mutating func apply(_ style: Style) {
        let preset = Settings.preset(style)
        manualLocksCanHaveDuration = preset.manualLocksCanHaveDuration
        touchGrassGivesBreak = preset.touchGrassGivesBreak
        looseningWaitsUntilTomorrow = preset.looseningWaitsUntilTomorrow
    }

    /// The style these settings match, or nil if they've been customised.
    public var style: Style? {
        Style.allCases.first { style in
            var candidate = self
            candidate.apply(style)
            return candidate == self
        }
    }
}
