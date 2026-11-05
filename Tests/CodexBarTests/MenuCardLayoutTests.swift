import CodexBarCore
import Foundation
import Testing

struct MenuCardLayoutTests {
    // MARK: - Defaults

    @Test
    func `default layout lists every section visible in today's order with the automatic chart`() {
        let layout = MenuCardLayout.default
        #expect(layout.order == [.usage, .pace, .chart, .credits, .extraUsage, .cost])
        #expect(layout.sections.allSatisfy(\.isVisible))
        #expect(layout.chart == .automatic)
        #expect(layout.hiddenMenuItems.isEmpty)
        #expect(layout.isDefault)
        #expect(layout.hasDefaultCard)
        #expect(MenuCardSectionKind.allCases.allSatisfy { MenuCardSectionKind.defaultOrder.contains($0) })
    }

    @Test
    func `default layout resolves to the built in card`() {
        let resolved = MenuCardLayout.default.resolved(for: .everything)
        #expect(resolved.sections == MenuCardSectionKind.defaultOrder)
        #expect(resolved.chart == .automatic)
        #expect(resolved.usesDefaultOrder)
    }

    @Test
    func `hidden menu links keep the card itself default`() {
        var layout = MenuCardLayout.default
        layout.setMenuItem(.statusPage, visible: false)
        #expect(!layout.isDefault)
        #expect(layout.hasDefaultCard)
        #expect(!layout.showsMenuItem(.statusPage))
        #expect(layout.showsMenuItem(.usageDashboard))
        layout.setMenuItem(.statusPage, visible: true)
        #expect(layout.isDefault)
    }

    // MARK: - Resolution

    @Test
    func `resolution drops hidden and unavailable sections`() {
        var layout = MenuCardLayout.default
        layout.setVisible(false, for: .credits)
        let availability = MenuCardLayoutAvailability(
            sections: [.usage, .credits, .cost, .chart],
            charts: [.live])
        let resolved = layout.resolved(for: availability)
        #expect(resolved.sections == [.usage, .chart, .cost])
        #expect(resolved.chart == .automatic)
        #expect(resolved.usesDefaultOrder)
    }

    @Test
    func `a chosen chart without data resolves to none instead of another chart`() {
        let layout = MenuCardLayout(chart: .burndown)
        let resolved = layout.resolved(for: MenuCardLayoutAvailability(
            sections: [.usage, .chart],
            charts: [.live, .spend]))
        #expect(resolved.chart == MenuCardChartChoice.none)
        #expect(!resolved.contains(.chart))

        let available = layout.resolved(for: MenuCardLayoutAvailability(sections: [.usage], charts: [.burndown]))
        #expect(available.chart == .burndown)
        #expect(available.contains(.chart))
    }

    @Test
    func `automatic needs a live or spend chart and a hidden chart section means none`() {
        let onlyHistory = MenuCardLayoutAvailability(sections: [.usage], charts: [.planFit])
        #expect(MenuCardLayout.default.resolved(for: onlyHistory).chart == MenuCardChartChoice.none)

        var hidden = MenuCardLayout(chart: .live)
        hidden.setVisible(false, for: .chart)
        let resolved = hidden.resolved(for: .everything)
        #expect(resolved.chart == MenuCardChartChoice.none)
        #expect(!resolved.contains(.chart))
    }

    @Test
    func `moving a section away from the default order turns off the built in arrangement`() {
        var layout = MenuCardLayout.default
        #expect(layout.move(.cost, by: -3))
        #expect(layout.order == [.usage, .pace, .cost, .chart, .credits, .extraUsage])
        let resolved = layout.resolved(for: .everything)
        #expect(!resolved.usesDefaultOrder)
        #expect(resolved.sections == [.usage, .pace, .cost, .chart, .credits, .extraUsage])

        // Only the relative order of sections the provider shows matters.
        let costAndCreditsMissing = layout.resolved(for: MenuCardLayoutAvailability(
            sections: [.usage, .extraUsage],
            charts: [.live]))
        #expect(costAndCreditsMissing.usesDefaultOrder)
    }

    @Test
    func `moves skip pace and stop at the ends`() {
        var layout = MenuCardLayout.default
        #expect(!layout.canMove(.usage, by: -1))
        #expect(!layout.move(.cost, by: 1))
        #expect(!layout.move(.pace, by: 1))
        #expect(layout.move(.chart, by: -1))
        #expect(layout.order == [.chart, .pace, .usage, .credits, .extraUsage, .cost])
        #expect(layout.reorderableSections.map(\.kind) == [.chart, .usage, .credits, .extraUsage, .cost])
    }

    @Test
    func `visibility survives a move`() {
        var layout = MenuCardLayout.default
        layout.setVisible(false, for: .credits)
        layout.move(.credits, by: -1)
        #expect(layout.order == [.usage, .pace, .credits, .chart, .extraUsage, .cost])
        #expect(!layout.isVisible(.credits))
        #expect(layout.isVisible(.chart))
    }

    // MARK: - Normalization

    @Test
    func `normalization keeps the first duplicate and inserts missing kinds at their default place`() {
        let stored: [MenuCardLayout.Section] = [
            .init(kind: .cost),
            .init(kind: .usage, isVisible: false),
            .init(kind: .cost, isVisible: false),
            .init(kind: .credits),
        ]
        let layout = MenuCardLayout(sections: stored)
        // pace and chart follow usage; extraUsage follows credits.
        #expect(layout.order == [.cost, .usage, .pace, .chart, .credits, .extraUsage])
        #expect(!layout.isVisible(.usage))
        #expect(layout.isVisible(.cost))
        #expect(layout.isVisible(.pace))
    }

    @Test
    func `a kind missing from an older layout appears in its default position`() {
        let olderLayout: [MenuCardLayout.Section] = [
            .init(kind: .usage),
            .init(kind: .pace),
            .init(kind: .credits),
            .init(kind: .extraUsage),
            .init(kind: .cost),
        ]
        #expect(MenuCardLayout(sections: olderLayout).order == MenuCardSectionKind.defaultOrder)
        #expect(MenuCardLayout(sections: []).order == MenuCardSectionKind.defaultOrder)
    }

    // MARK: - Codable

    @Test
    func `layouts round trip through json`() throws {
        var layout = MenuCardLayout(chart: .planFit)
        layout.move(.extraUsage, by: -3)
        layout.setVisible(false, for: .pace)
        layout.setMenuItem(.usageDashboard, visible: false)
        let json = try #require(layout.encodedJSON())
        #expect(MenuCardLayout.decoded(fromJSON: json) == layout)
        #expect(json == layout.encodedJSON())
    }

    @Test
    func `decoding drops unknown kinds and tolerates bad values`() throws {
        let json = """
        {
          "sections": [
            {"kind": "sparkles", "visible": false},
            {"kind": "credits", "visible": false},
            42,
            {"visible": true},
            {"kind": "usage"}
          ],
          "chart": "hologram",
          "hiddenMenuItems": ["statusPage", "fax"],
          "futureField": true
        }
        """
        let layout = try #require(MenuCardLayout.decoded(fromJSON: json))
        #expect(layout.order.first == .credits)
        #expect(!layout.isVisible(.credits))
        #expect(layout.isVisible(.usage))
        #expect(Set(layout.order) == Set(MenuCardSectionKind.allCases))
        #expect(layout.order.count == MenuCardSectionKind.allCases.count)
        #expect(layout.chart == .automatic)
        #expect(layout.hiddenMenuItems == [.statusPage])
    }

    @Test
    func `decoding an empty object gives the default and garbage gives nil`() {
        #expect(MenuCardLayout.decoded(fromJSON: "{}") == .default)
        #expect(MenuCardLayout.decoded(fromJSON: "not json") == nil)
        #expect(MenuCardLayout.decoded(fromJSON: "[1, 2]") == nil)
    }
}
