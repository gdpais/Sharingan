import AppKit
import CodexBarCore
import SwiftUI

/// Runway submenu that hosts its chart only when AppKit is about to show it, so building the parent
/// menu never pays for a SwiftUI chart. It is its own delegate and stays out of the controller's
/// hosted-subview tracking.
final class BalanceRunwaySubmenu: NSMenu, NSMenuDelegate {
    var pendingChart: BalanceRunwayChartMenuView?
    var chartWidth: CGFloat = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let chart = self.pendingChart else { return }
        self.pendingChart = nil

        let hosting = MenuHostingView(rootView: chart)
        hosting.applyMeasuredHeight(width: self.chartWidth, height: BalanceRunwayChartMenuView.preferredHeight)
        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = true
        chartItem.representedObject = StatusItemController.balanceRunwayChartID
        self.removeAllItems()
        self.addItem(chartItem)
    }
}

extension StatusItemController {
    static let balanceRunwaySubmenuID = "balanceRunwaySubmenu"
    static let balanceRunwayChartID = "balanceRunwayChart"

    /// Adds "Lasts until … at this rate" under the provider's card, with the runway chart as its submenu.
    /// Nothing is added without a balance on the card or enough declining history for an estimate.
    func addBalanceRunwayMenuItemIfNeeded(to menu: NSMenu, context: MenuCardContext) {
        // Stacked account cards would leave it unclear which account the runway describes.
        guard context.tokenAccountDisplay?.showAll != true,
              context.codexAccountDisplay?.showAll != true,
              !ClaudeSwapMenuPrecedence.prefersClaudeSwap(
                  provider: context.currentProvider,
                  accountCount: self.store.claudeSwapAccountSnapshots.count,
                  showSingleAccount: self.settings.claudeSwapShowSingleAccount),
              let model = self.store.balanceRunwayChartModel(for: context.currentProvider)
        else { return }

        let item = NSMenuItem(
            title: BalanceRunwayChartMenuView.lastsUntilText(
                model.estimate.depletionDate,
                relativeTo: model.estimate.observedAt),
            action: nil,
            keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = Self.balanceRunwaySubmenuID
        item.submenu = self.makeBalanceRunwaySubmenu(model: model, width: context.menuWidth)

        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        menu.addItem(item)
        menu.addItem(.separator())
    }

    func makeBalanceRunwaySubmenu(model: BalanceRunwayChartModel, width: CGFloat) -> NSMenu {
        let submenu = BalanceRunwaySubmenu(title: "")
        submenu.autoenablesItems = false
        submenu.minimumWidth = width
        submenu.delegate = submenu

        // A placeholder keeps the submenu non-empty until the chart is hosted on first display.
        let placeholder = NSMenuItem()
        placeholder.isEnabled = true
        placeholder.representedObject = Self.balanceRunwayChartID
        submenu.addItem(placeholder)

        if self.menuCardRenderingEnabledForController {
            submenu.chartWidth = width
            submenu.pendingChart = BalanceRunwayChartMenuView(
                model: model,
                display: self.balanceRunwayDisplay(currencyCode: model.estimate.currencyCode),
                width: width)
        }
        return submenu
    }

    /// Converts ISO-currency balances into the preferred display currency, like the card's balance line.
    /// Provider units such as credits or points are shown as plain numbers.
    private func balanceRunwayDisplay(currencyCode: String) -> BalanceRunwayChartMenuView.Display {
        let isISOCurrency = currencyCode.count == 3 && currencyCode.allSatisfy { $0.isASCII && $0.isUppercase }
        guard isISOCurrency else { return .providerUnits }
        let converted = UsageFormatter.convertedCost(
            1,
            preferredCurrency: self.settings.preferredCurrencyCode,
            providerCurrency: currencyCode)
        return BalanceRunwayChartMenuView.Display(currencyCode: converted.currencyCode, multiplier: converted.value)
    }
}
