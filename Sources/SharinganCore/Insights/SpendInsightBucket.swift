import Foundation

/// Calendar buckets for insight charts, so long ranges read as weeks or months instead of hundreds of days.
public enum SpendInsightBucket: String, CaseIterable, Equatable, Sendable {
    case day
    case week
    case month

    public var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// Start of the bucket that contains `date` in `calendar`.
    public func start(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: self.calendarComponent, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
