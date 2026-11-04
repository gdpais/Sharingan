import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct BalanceRunwayChartMenuViewTests {
    private static let start = Date(timeIntervalSince1970: 1_686_830_400)

    private static func chartModel() throws -> BalanceRunwayChartModel {
        let samples = (0...5).map { day in
            BalanceHistorySample(
                capturedAt: self.start.addingTimeInterval(Double(day) * 86400),
                balance: 10 - Double(day),
                currencyCode: "USD")
        }
        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))
        return try #require(BalanceRunwayChartModel(samples: samples, estimate: estimate))
    }

    @Test
    func `lasts until text names the depletion date`() {
        let date = Self.start.addingTimeInterval(10 * 86400)
        let dateText = BalanceRunwayChartMenuView.dateText(date, relativeTo: Self.start)

        #expect(BalanceRunwayChartMenuView.lastsUntilText(date, relativeTo: Self.start).contains(dateText))
    }

    @Test
    func `dates add the year only when it differs from the reference`() {
        let nextYear = Self.start.addingTimeInterval(400 * 86400)

        #expect(
            BalanceRunwayChartMenuView.dateText(nextYear, relativeTo: Self.start) !=
                BalanceRunwayChartMenuView.dateText(nextYear, relativeTo: nextYear))
    }

    @Test
    func `amounts use the display currency or provider units`() {
        let dollars = BalanceRunwayChartMenuView.Display(currencyCode: "USD", multiplier: 1)
        let halfEuros = BalanceRunwayChartMenuView.Display(currencyCode: "EUR", multiplier: 0.5)

        #expect(BalanceRunwayChartMenuView.amountText(12.5, display: dollars) == "$12.50")
        #expect(BalanceRunwayChartMenuView.amountText(10, display: halfEuros) == "€5.00")
        #expect(BalanceRunwayChartMenuView.amountText(12.5, display: .providerUnits) == "12.5")
    }

    @Test
    func `runway submenu hosts its chart once on first display`() throws {
        let submenu = BalanceRunwaySubmenu(title: "")
        submenu.addItem(NSMenuItem())
        submenu.chartWidth = 300
        submenu.pendingChart = try BalanceRunwayChartMenuView(
            model: Self.chartModel(),
            display: .init(currencyCode: "USD", multiplier: 1),
            width: 300)

        submenu.menuNeedsUpdate(submenu)
        let hosted = submenu.items.first?.view
        submenu.menuNeedsUpdate(submenu)

        #expect(submenu.items.count == 1)
        #expect(hosted != nil)
        #expect(submenu.items.first?.view === hosted)
        #expect(submenu.items.first?.representedObject as? String == StatusItemController.balanceRunwayChartID)
        #expect(hosted?.frame.height == BalanceRunwayChartMenuView.preferredHeight)
        #expect(submenu.pendingChart == nil)
    }
}
