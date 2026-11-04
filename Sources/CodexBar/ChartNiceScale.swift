import Foundation

/// Pure 1-2-5 "nice number" rounding shared by menu charts and bar strips.
enum ChartNiceScale {
    private static let mantissas: [Double] = [1, 2, 5, 10]

    /// Smallest `m × 10ⁿ` (m ∈ 1, 2, 5) at or above `value`, or strictly above it when `strictlyAbove` is set.
    /// Returns nil for non-finite, zero, or negative input, or when the result overflows.
    static func niceValue(atLeast value: Double, strictlyAbove: Bool = false) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        let magnitude = pow(10, floor(log10(value)))
        guard magnitude.isFinite, magnitude > 0 else { return nil }
        let normalized = value / magnitude
        let mantissa = self.mantissas.first { strictlyAbove ? $0 > normalized : $0 >= normalized } ?? 10
        let result = mantissa * magnitude
        return result.isFinite ? result : nil
    }

    /// Evenly spaced ticks from zero to a nice ceiling at or above `maximum`.
    ///
    /// The step is the nice value covering `maximum / targetIntervals` (never below `minimumStep`), so a
    /// four-interval target yields three to five ticks. The last tick is the nice ceiling the y domain
    /// should extend to. Returns an empty array for flat, negative, or non-finite input.
    static func ticks(maximum: Double, targetIntervals: Int = 4, minimumStep: Double = 0) -> [Double] {
        guard maximum.isFinite, maximum > 0, targetIntervals > 0 else { return [] }
        let rawStep = max(maximum / Double(targetIntervals), minimumStep)
        guard let step = self.niceValue(atLeast: rawStep) else { return [] }
        // Absorb floating-point noise such as 0.07 / 0.01 = 7.000000000000001.
        let intervals = max(1, Int((maximum / step - 1e-9).rounded(.up)))
        let decimals = max(0, -Int(floor(log10(step))))
        let factor = pow(10, Double(decimals))
        return (0...intervals).map { index in
            (Double(index) * step * factor).rounded() / factor
        }
    }
}
