import Foundation
import SharinganCore

extension CodexHistoricalDataset {
    /// Past weekly curves in the shape the typical-week model reads.
    var typicalWeekInputs: [TypicalWeekCurve.Week] {
        self.weeks.map { week in
            TypicalWeekCurve.Week(resetsAt: week.resetsAt, windowMinutes: week.windowMinutes, usedPercent: week.curve)
        }
    }
}

@MainActor
extension UsageStore {
    /// Past weekly usage curves for the burndown's typical-week band, or none when nothing was learned.
    ///
    /// Uses the same opt-in history and account scoping as the learned pace, so the band never shows another
    /// account's weeks.
    func typicalWeekInputs(for provider: UsageProvider) -> [TypicalWeekCurve.Week] {
        // Provider-specific by design: only Codex records account-scoped weekly curves (learned pace).
        guard provider == .codex,
              self.settings.historicalTrackingEnabled,
              let dataset = self.codexHistoricalDataset,
              self.codexHistoricalDatasetAccountKey == self.codexOwnershipContext().canonicalKey
        else { return [] }
        return dataset.typicalWeekInputs
    }
}
