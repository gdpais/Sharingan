import Foundation

/// Folds hourly usage into a weekday × hour-of-day grid, so heavy work can be lined up with resets.
///
/// Samples bucket by wall-clock components in `calendar`'s time zone. A 25-hour DST day folds both
/// occurrences of the repeated hour into one cell; a 23-hour day simply has no sample for the
/// skipped hour. Rows start at `calendar.firstWeekday`.
public struct HourOfWeekHeatmapModel: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public let hour: Date
        /// `nil`, negative or non-finite costs are left out of every cost total.
        public let cost: Double?
        /// `nil` or negative token counts are left out of every token total.
        public let tokens: Int?

        public init(hour: Date, cost: Double?, tokens: Int? = nil) {
            self.hour = hour
            self.cost = cost
            self.tokens = tokens
        }
    }

    public struct Cell: Sendable, Equatable, Identifiable {
        /// Display row; `0` is the calendar's first weekday.
        public let row: Int
        /// `Calendar` weekday number (1 is Sunday in the Gregorian calendar).
        public let weekday: Int
        /// Wall-clock hour in `0..<24`.
        public let hour: Int
        public let cost: Double
        /// `nil` when no sample folded into this cell reported tokens.
        public let tokens: Int?
        /// Hourly samples folded into this cell.
        public let sampleCount: Int
        /// Fraction of the grid's total cost; `0` when the grid has no spend.
        public let share: Double
        /// Cost relative to the busiest cell, in `0...1`.
        public let intensity: Double
        public let isWeekend: Bool

        public var id: Int {
            self.row * HourOfWeekHeatmapModel.hoursPerDay + self.hour
        }
    }

    public static let daysPerWeek = 7
    public static let hoursPerDay = 24

    /// `Calendar` weekday numbers in display order, starting at `calendar.firstWeekday`.
    public let weekdays: [Int]
    /// `daysPerWeek * hoursPerDay` cells, row-major in display order.
    public let cells: [Cell]
    public let sampleCount: Int
    public let totalCost: Double
    /// `nil` when no sample reported tokens.
    public let totalTokens: Int?
    public let maxCost: Double
    public let maxTokens: Int?
    /// Highest-cost cell; ties keep the earliest cell in display order. `nil` without positive spend.
    public let busiestCell: Cell?
    public let weekendCost: Double
    /// Fraction of the total cost spent on weekend days; `nil` without positive spend.
    public let weekendShare: Double?

    /// - Parameter weekendWeekdays: `Calendar` weekday numbers counted as the weekend
    ///   (Saturday and Sunday by default).
    public init(samples: [Sample], calendar: Calendar, weekendWeekdays: Set<Int> = [1, 7]) {
        let days = Self.daysPerWeek
        let hours = Self.hoursPerDay
        let firstWeekday = (1...days).contains(calendar.firstWeekday) ? calendar.firstWeekday : 1
        let weekdays = (0..<days).map { (firstWeekday - 1 + $0) % days + 1 }
        var costs = [Double](repeating: 0, count: days * hours)
        var tokens = [Int?](repeating: nil, count: days * hours)
        var counts = [Int](repeating: 0, count: days * hours)
        var sampleCount = 0
        for sample in samples {
            let components = calendar.dateComponents([.weekday, .hour], from: sample.hour)
            guard let weekday = components.weekday, (1...days).contains(weekday),
                  let hour = components.hour, (0..<hours).contains(hour)
            else { continue }
            let index = ((weekday - firstWeekday + days) % days) * hours + hour
            sampleCount += 1
            counts[index] += 1
            if let cost = sample.cost, cost.isFinite, cost >= 0 {
                costs[index] = Self.finiteSum(costs[index], cost)
            }
            if let count = sample.tokens, count >= 0 {
                tokens[index] = Self.saturatingSum(tokens[index] ?? 0, count)
            }
        }

        let totalCost = costs.reduce(0, Self.finiteSum)
        let maxCost = costs.max() ?? 0
        let knownTokens = tokens.compactMap(\.self)
        var cells: [Cell] = []
        cells.reserveCapacity(days * hours)
        var busiest: Cell?
        var weekendCost = 0.0
        for row in 0..<days {
            let weekday = weekdays[row]
            let isWeekend = weekendWeekdays.contains(weekday)
            for hour in 0..<hours {
                let index = row * hours + hour
                let cost = costs[index]
                let cell = Cell(
                    row: row,
                    weekday: weekday,
                    hour: hour,
                    cost: cost,
                    tokens: tokens[index],
                    sampleCount: counts[index],
                    share: totalCost > 0 ? cost / totalCost : 0,
                    intensity: maxCost > 0 ? min(1, cost / maxCost) : 0,
                    isWeekend: isWeekend)
                cells.append(cell)
                if cost > 0, cost > (busiest?.cost ?? 0) {
                    busiest = cell
                }
                if isWeekend {
                    weekendCost = Self.finiteSum(weekendCost, cost)
                }
            }
        }

        self.weekdays = weekdays
        self.cells = cells
        self.sampleCount = sampleCount
        self.totalCost = totalCost
        self.totalTokens = knownTokens.isEmpty ? nil : knownTokens.reduce(0, Self.saturatingSum)
        self.maxCost = maxCost
        self.maxTokens = knownTokens.max()
        self.busiestCell = busiest
        self.weekendCost = weekendCost
        self.weekendShare = totalCost > 0 ? min(1, weekendCost / totalCost) : nil
    }

    /// No sample landed in the grid.
    public var isEmpty: Bool {
        self.sampleCount == 0
    }

    /// - Parameters:
    ///   - row: Display row in `0..<daysPerWeek`.
    ///   - hour: Wall-clock hour in `0..<hoursPerDay`.
    public func cell(row: Int, hour: Int) -> Cell? {
        guard (0..<Self.daysPerWeek).contains(row), (0..<Self.hoursPerDay).contains(hour) else { return nil }
        return self.cells[row * Self.hoursPerDay + hour]
    }

    /// - Parameter weekday: `Calendar` weekday number.
    public func cell(weekday: Int, hour: Int) -> Cell? {
        guard let row = self.weekdays.firstIndex(of: weekday) else { return nil }
        return self.cell(row: row, hour: hour)
    }

    /// Sequential color level: `0` for no spend, then `1...levelCount` by equal fractions of the
    /// busiest cell, matching the token-activity heatmap's quartile ramp for `levelCount == 4`.
    public func level(of cell: Cell, levelCount: Int = 4) -> Int {
        guard levelCount > 0, cell.cost > 0, self.maxCost > 0 else { return 0 }
        let scaled = (cell.intensity * Double(levelCount)).rounded(.up)
        return min(levelCount, max(1, Int(scaled)))
    }

    private static func finiteSum(_ lhs: Double, _ rhs: Double) -> Double {
        let sum = lhs + rhs
        return sum.isFinite ? sum : .greatestFiniteMagnitude
    }

    private static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}
