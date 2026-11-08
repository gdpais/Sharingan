import Foundation
import SharinganCore

extension StatusItemController {
    /// Cost of the window before the History window for the cost history submenu, or nil when the
    /// token refresh could not read it in full (see `CostHistoryChartMenuView.previousPeriodCostUSD`).
    func costHistoryPreviousPeriodCost(for snapshot: CostUsageTokenSnapshot) -> Double? {
        let calendar = self.settings.costUsageBucketCalendar
        return CostHistoryChartMenuView.previousPeriodCostUSD(
            snapshot,
            historyDays: snapshot.displayHistoryDays(calendar: calendar),
            calendar: calendar)
    }
}
