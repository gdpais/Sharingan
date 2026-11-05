import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct PlanUtilizationHistoryChartMenuView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 130
        static let detailHeight: CGFloat = 16
        static let emptyStateHeight: CGFloat = chartHeight + detailHeight
        static let maxPoints = 30
        static let maxAxisLabels = 4
        static let barWidth: CGFloat = 6
    }

    struct SeriesSelection: Hashable {
        let name: PlanUtilizationSeriesName
        let windowMinutes: Int

        var id: String {
            "\(self.name.rawValue):\(self.windowMinutes)"
        }
    }

    struct VisibleSeries: Identifiable, Equatable {
        let selection: SeriesSelection
        let title: String
        let history: PlanUtilizationSeriesHistory

        var id: String {
            self.selection.id
        }
    }

    private struct EntryPointAccumulator {
        let effectiveBoundaryDate: Date
        let displayBoundaryDate: Date
        let observedAt: Date
        let usedPercent: Double
        let hasObservedResetBoundary: Bool
    }

    private struct ResetBoundaryLattice {
        let referenceBoundaryDate: Date
        let windowInterval: TimeInterval
    }

    private struct Point: Identifiable {
        let id: Date
        let index: Int
        let date: Date
        let usedPercent: Double
        let isObserved: Bool
    }

    private struct Model {
        let points: [Point]
        let axisIndexes: [Double]
        let xDomain: ClosedRange<Double>?
        let pointsByID: [Date: Point]
        let pointsByIndex: [Int: Point]
        let barColor: Color
        let trackColor: Color
        let fit: PlanFitChartParts
    }

    private let provider: UsageProvider
    private let visibleSeries: [VisibleSeries]
    private let modelsBySeriesID: [String: Model]
    private let emptyModel: Model
    private let width: CGFloat
    private let onSeriesChanged: (@MainActor (String) -> Void)?

    @State private var selectedSeriesID: String?
    @State private var selectedPointID: Date?

    init(
        provider: UsageProvider,
        histories: [PlanUtilizationSeriesHistory],
        snapshot: UsageSnapshot? = nil,
        width: CGFloat,
        referenceDate: Date = Date(),
        initialSeriesID: String? = nil,
        onSeriesChanged: (@MainActor (String) -> Void)? = nil)
    {
        self.provider = provider
        let visibleSeries = Self.visibleSeries(
            histories: histories,
            provider: provider,
            snapshot: snapshot)
        self.visibleSeries = visibleSeries
        self.modelsBySeriesID = Dictionary(uniqueKeysWithValues: visibleSeries.map {
            ($0.id, Self.makeModel(history: $0.history, provider: provider, referenceDate: referenceDate, width: width))
        })
        self.emptyModel = Self.makeModel(history: nil, provider: provider, referenceDate: referenceDate, width: width)
        self.width = width
        self.onSeriesChanged = onSeriesChanged
        self._selectedSeriesID = State(initialValue: Self.restoredSeriesID(
            initialSeriesID,
            visibleSeries: visibleSeries))
    }

    var body: some View {
        let effectiveSelectedSeries = self.visibleSeries.first(where: { $0.id == self.selectedSeriesID })
            ?? self.visibleSeries.first
        let model = effectiveSelectedSeries.flatMap { self.modelsBySeriesID[$0.id] } ?? self.emptyModel

        VStack(alignment: .leading, spacing: 10) {
            if self.visibleSeries.count > 1 {
                Picker(selection: Binding(
                    get: { effectiveSelectedSeries?.id ?? "" },
                    set: { newValue in
                        self.selectedSeriesID = newValue
                        self.selectedPointID = nil
                        self.onSeriesChanged?(newValue)
                    })) {
                        ForEach(self.visibleSeries) { series in
                            Text(series.title).tag(series.id)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                        .pickerStyle(.segmented)
            }

            if model.points.isEmpty {
                ZStack {
                    Text(Self.emptyStateText(title: effectiveSelectedSeries?.title))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.emptyStateHeight + self.planFitFooterHeight)
            } else {
                self.utilizationChart(model: model)
                    .chartYAxis { Self.percentAxisMarks() }
                    .chartYScale(domain: 0...PlanFitChartLayout.yDomainTop)
                    .chartXAxis {
                        AxisMarks(values: model.axisIndexes) { value in
                            AxisGridLine().foregroundStyle(Color.clear)
                            AxisTick().foregroundStyle(Color.clear)
                            AxisValueLabel(anchor: ChartAxisLabelLayout.barCenteredAnchor) {
                                if let raw = value.as(Double.self) {
                                    let index = Int(raw.rounded())
                                    if let point = model.pointsByIndex[index] {
                                        Self.axisLabel(
                                            for: point,
                                            windowMinutes: effectiveSelectedSeries?.history.windowMinutes ?? 0)
                                    }
                                }
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: Layout.chartHeight)
                    .accessibilityLabel(L("Plan utilization chart"))
                    .accessibilityValue(
                        model.points.isEmpty
                            ? L("No data")
                            : String(format: L("%d utilization samples"), model.points.count))
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            MouseLocationReader { location in
                                self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                    }

                self.chartFooter(model: model, windowMinutes: effectiveSelectedSeries?.history.windowMinutes ?? 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .topLeading)
        .task(id: self.visibleSeries.map(\.id).joined(separator: ",")) {
            guard let firstVisibleSeries = self.visibleSeries.first else { return }
            guard !self.visibleSeries.contains(where: { $0.id == self.selectedSeriesID }) else { return }
            self.selectedSeriesID = firstVisibleSeries.id
            self.selectedPointID = nil
        }
        .codexBarLocalized()
    }

    nonisolated static func visibleSeries(
        histories: [PlanUtilizationSeriesHistory],
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> [VisibleSeries]
    {
        let metadata = ProviderDescriptorRegistry.metadata[provider]
        // Provider-specific by design: Antigravity pool observations have no session/weekly cadence.
        let usesObservations = provider == .antigravity && UsageStore.antigravityHistoryUsesObservations(
            snapshot: snapshot, histories: histories)
        let allowedNames = usesObservations ? nil : self.visibleSeriesNames(provider: provider, snapshot: snapshot)
        var historiesBySelection: [SeriesSelection: PlanUtilizationSeriesHistory] = [:]
        for history in histories {
            guard !history.entries.isEmpty else { continue }
            guard history.hasSupportedCadence, history.name.isQuotaObservation == usesObservations else { continue }
            let effectiveName = Self.effectiveSeriesName(provider: provider, history: history)
            guard allowedNames?.contains(effectiveName) ?? true else { continue }

            let canonicalWindowMinutes = effectiveName.canonicalWindowMinutes(history.windowMinutes)
            let selection = SeriesSelection(name: effectiveName, windowMinutes: canonicalWindowMinutes)
            if let existingHistory = historiesBySelection[selection] {
                historiesBySelection[selection] = PlanUtilizationSeriesHistory(
                    name: effectiveName,
                    windowMinutes: canonicalWindowMinutes,
                    entries: Self.mergedEntries(existingHistory.entries + history.entries))
            } else {
                historiesBySelection[selection] = PlanUtilizationSeriesHistory(
                    name: effectiveName,
                    windowMinutes: canonicalWindowMinutes,
                    entries: history.entries)
            }
        }

        return historiesBySelection.values
            .sorted { lhs, rhs in
                let lhsOrder = self.seriesSortOrder(lhs.name)
                let rhsOrder = self.seriesSortOrder(rhs.name)
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                if lhs.windowMinutes != rhs.windowMinutes {
                    return lhs.windowMinutes < rhs.windowMinutes
                }
                return lhs.name.rawValue < rhs.name.rawValue
            }
            .map { history in
                VisibleSeries(
                    selection: SeriesSelection(name: history.name, windowMinutes: history.windowMinutes),
                    title: self.seriesTitle(
                        name: history.name,
                        metadata: metadata,
                        windowMinutes: history.windowMinutes),
                    history: history)
            }
    }

    /// A remembered series is restored only while it is still visible; nil falls back to the first series.
    nonisolated static func restoredSeriesID(_ seriesID: String?, visibleSeries: [VisibleSeries]) -> String? {
        guard let seriesID, visibleSeries.contains(where: { $0.id == seriesID }) else { return nil }
        return seriesID
    }

    /// Histories recorded before duration-based classification stored a 43,200-minute Codex window
    /// under its payload slot (session for primary, weekly for secondary). Fold those into the
    /// monthly series so the chart does not split or hide the window's history.
    private nonisolated static func effectiveSeriesName(
        provider: UsageProvider,
        history: PlanUtilizationSeriesHistory) -> PlanUtilizationSeriesName
    {
        if history.name.isQuotaObservation { return history.name }
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation
        let normalized = presentation.normalizePlanUtilizationSeries(
            self.providerSeries(history.name),
            windowMinutes: history.windowMinutes)
        return self.historySeries(normalized)
    }

    nonisolated static func mergedEntries(
        _ entries: [PlanUtilizationHistoryEntry]) -> [PlanUtilizationHistoryEntry]
    {
        var seen: Set<PlanUtilizationHistoryEntry> = []
        return entries.filter { entry in
            seen.insert(entry).inserted
        }
    }

    private nonisolated static func visibleSeriesNames(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> Set<PlanUtilizationSeriesName>?
    {
        guard let snapshot else { return nil }

        return ProviderDescriptorRegistry.descriptor(for: provider).presentation
            .planUtilizationSeries(snapshot: snapshot)
            .map { Set($0.map(self.historySeries)) }
    }

    private nonisolated static func providerSeries(
        _ series: PlanUtilizationSeriesName) -> ProviderPlanUtilizationSeries
    {
        switch series {
        case .session: .session
        case .weekly: .weekly
        case .opus: .tertiary
        case .monthly: .monthly
        default: .weekly
        }
    }

    private nonisolated static func historySeries(
        _ series: ProviderPlanUtilizationSeries) -> PlanUtilizationSeriesName
    {
        switch series {
        case .session: .session
        case .weekly: .weekly
        case .tertiary: .opus
        case .monthly: .monthly
        }
    }

    private nonisolated static func makeModel(
        history: PlanUtilizationSeriesHistory?,
        provider: UsageProvider,
        referenceDate: Date,
        width: CGFloat) -> Model
    {
        var points = history.map { self.seriesPoints(history: $0, referenceDate: referenceDate) } ?? []
        if points.count > Layout.maxPoints {
            points = Array(points.suffix(Layout.maxPoints))
        }

        points = points.enumerated().map { offset, point in
            Point(
                id: point.id,
                index: offset,
                date: point.date,
                usedPercent: point.usedPercent,
                isObserved: point.isObserved)
        }

        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        let pointsByIndex = Dictionary(uniqueKeysWithValues: points.map { ($0.index, $0) })
        let color = ProviderAccentPalette.color(for: provider)
        let barColor = Color(red: color.red, green: color.green, blue: color.blue)
        let trackColor = MenuHighlightStyle.progressTrack(false)
        let fit = self.planFitParts(
            history: history, points: points, accent: color, referenceDate: referenceDate, width: width)

        return Model(
            points: points,
            axisIndexes: self.axisIndexes(points: points, windowMinutes: history?.windowMinutes ?? 0, fit: fit),
            xDomain: self.xDomain(points: points, slotCount: fit.slotCount),
            pointsByID: pointsByID,
            pointsByIndex: pointsByIndex,
            barColor: barColor,
            trackColor: trackColor,
            fit: fit)
    }

    private nonisolated static func seriesPoints(
        history: PlanUtilizationSeriesHistory,
        referenceDate: Date) -> [Point]
    {
        if history.windowMinutes == 0, history.name.isQuotaObservation {
            // These are actual capture times, not inferred reset cycles. Never manufacture gaps.
            let entries = Dictionary(grouping: history.entries, by: \.capturedAt)
            return entries.keys.sorted().compactMap { date in
                guard let entry = entries[date]?.last else { return nil }
                return Point(id: date, index: 0, date: date, usedPercent: entry.usedPercent, isObserved: true)
            }
        }
        guard history.windowMinutes > 0 else { return [] }
        let windowInterval = Double(history.windowMinutes) * 60
        let resetBoundaryLattice = self.resetBoundaryLattice(
            entries: history.entries,
            windowMinutes: history.windowMinutes)
        var strongestObservedPointByPeriod: [Date: EntryPointAccumulator] = [:]

        for entry in history.entries {
            let candidate = self.observedPointCandidate(
                for: entry,
                windowMinutes: history.windowMinutes,
                resetBoundaryLattice: resetBoundaryLattice)

            if let existing = strongestObservedPointByPeriod[candidate.effectiveBoundaryDate],
               !self.shouldPreferObservedPoint(candidate, over: existing)
            {
                continue
            }
            strongestObservedPointByPeriod[candidate.effectiveBoundaryDate] = candidate
        }

        guard !strongestObservedPointByPeriod.isEmpty else { return [] }

        let sortedPeriodBoundaryDates = strongestObservedPointByPeriod.keys.sorted()
        var points: [Point] = []
        var previousPeriodBoundaryDate: Date?

        for periodBoundaryDate in sortedPeriodBoundaryDates {
            if let previousPeriodBoundaryDate {
                var cursor = previousPeriodBoundaryDate.addingTimeInterval(windowInterval)
                while cursor < periodBoundaryDate {
                    points.append(Point(
                        id: cursor,
                        index: 0,
                        date: cursor,
                        usedPercent: 0,
                        isObserved: false))
                    cursor = cursor.addingTimeInterval(windowInterval)
                }
            }

            if let bucket = strongestObservedPointByPeriod[periodBoundaryDate] {
                points.append(Point(
                    id: bucket.effectiveBoundaryDate,
                    index: 0,
                    date: bucket.displayBoundaryDate,
                    usedPercent: bucket.usedPercent,
                    isObserved: true))
            }
            previousPeriodBoundaryDate = periodBoundaryDate
        }

        if let lastObservedPeriodBoundaryDate = sortedPeriodBoundaryDates.last {
            let currentPeriodBoundaryDate = self.currentPeriodBoundaryDate(
                for: referenceDate,
                windowMinutes: history.windowMinutes,
                resetBoundaryLattice: resetBoundaryLattice)

            if currentPeriodBoundaryDate > lastObservedPeriodBoundaryDate {
                var cursor = lastObservedPeriodBoundaryDate.addingTimeInterval(windowInterval)
                while cursor <= currentPeriodBoundaryDate {
                    points.append(Point(
                        id: cursor,
                        index: 0,
                        date: cursor,
                        usedPercent: 0,
                        isObserved: false))
                    cursor = cursor.addingTimeInterval(windowInterval)
                }
            }
        }

        return points
    }

    private nonisolated static func observedPointCandidate(
        for entry: PlanUtilizationHistoryEntry,
        windowMinutes: Int,
        resetBoundaryLattice: ResetBoundaryLattice?) -> EntryPointAccumulator
    {
        let rawResetBoundaryDate = entry.resetsAt.map(self.normalizedBoundaryDate)
        let effectiveBoundaryDate = self.effectivePeriodBoundaryDate(
            for: entry,
            windowMinutes: windowMinutes,
            rawResetBoundaryDate: rawResetBoundaryDate,
            resetBoundaryLattice: resetBoundaryLattice)
        return EntryPointAccumulator(
            effectiveBoundaryDate: effectiveBoundaryDate,
            displayBoundaryDate: rawResetBoundaryDate ?? effectiveBoundaryDate,
            observedAt: entry.capturedAt,
            usedPercent: max(0, min(100, entry.usedPercent)),
            hasObservedResetBoundary: rawResetBoundaryDate != nil)
    }

    private nonisolated static func resetBoundaryLattice(
        entries: [PlanUtilizationHistoryEntry],
        windowMinutes: Int) -> ResetBoundaryLattice?
    {
        guard let latestObservedResetBoundaryDate = entries
            .compactMap(\.resetsAt)
            .map(self.normalizedBoundaryDate)
            .max()
        else {
            return nil
        }
        return ResetBoundaryLattice(
            referenceBoundaryDate: latestObservedResetBoundaryDate,
            windowInterval: Double(windowMinutes) * 60)
    }

    private nonisolated static func normalizedBoundaryDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private nonisolated static func effectivePeriodBoundaryDate(
        for entry: PlanUtilizationHistoryEntry,
        windowMinutes: Int,
        rawResetBoundaryDate: Date?,
        resetBoundaryLattice: ResetBoundaryLattice?) -> Date
    {
        if let rawResetBoundaryDate {
            if let resetBoundaryLattice {
                return self.closestPeriodBoundaryDate(
                    to: rawResetBoundaryDate,
                    resetBoundaryLattice: resetBoundaryLattice)
            }
            return rawResetBoundaryDate
        }
        if let resetBoundaryLattice {
            return self.periodBoundaryDate(
                containing: entry.capturedAt,
                resetBoundaryLattice: resetBoundaryLattice)
        }
        return self.syntheticBoundaryDate(for: entry.capturedAt, windowMinutes: windowMinutes)
    }

    private nonisolated static func shouldPreferObservedPoint(
        _ candidate: EntryPointAccumulator,
        over existing: EntryPointAccumulator) -> Bool
    {
        if candidate.usedPercent != existing.usedPercent {
            return candidate.usedPercent > existing.usedPercent
        }
        if candidate.hasObservedResetBoundary != existing.hasObservedResetBoundary {
            return candidate.hasObservedResetBoundary
        }
        if candidate.displayBoundaryDate != existing.displayBoundaryDate {
            return candidate.displayBoundaryDate > existing.displayBoundaryDate
        }
        return candidate.observedAt >= existing.observedAt
    }

    private nonisolated static func currentPeriodBoundaryDate(
        for referenceDate: Date,
        windowMinutes: Int,
        resetBoundaryLattice: ResetBoundaryLattice?) -> Date
    {
        if let resetBoundaryLattice {
            return self.periodBoundaryDate(
                containing: referenceDate,
                resetBoundaryLattice: resetBoundaryLattice)
        }
        return self.syntheticBoundaryDate(for: referenceDate, windowMinutes: windowMinutes)
    }

    private nonisolated static func closestPeriodBoundaryDate(
        to rawBoundaryDate: Date,
        resetBoundaryLattice: ResetBoundaryLattice) -> Date
    {
        let offset = rawBoundaryDate.timeIntervalSince(resetBoundaryLattice.referenceBoundaryDate)
        let periodOffset = (offset / resetBoundaryLattice.windowInterval).rounded()
        return resetBoundaryLattice.referenceBoundaryDate
            .addingTimeInterval(periodOffset * resetBoundaryLattice.windowInterval)
    }

    private nonisolated static func periodBoundaryDate(
        containing capturedAt: Date,
        resetBoundaryLattice: ResetBoundaryLattice) -> Date
    {
        let offset = capturedAt.timeIntervalSince(resetBoundaryLattice.referenceBoundaryDate)
        let periodOffset = ceil(offset / resetBoundaryLattice.windowInterval)
        return resetBoundaryLattice.referenceBoundaryDate
            .addingTimeInterval(periodOffset * resetBoundaryLattice.windowInterval)
    }

    private nonisolated static func syntheticBoundaryDate(for date: Date, windowMinutes: Int) -> Date {
        let bucketSeconds = Double(windowMinutes) * 60
        let bucketIndex = floor(date.timeIntervalSince1970 / bucketSeconds)
        return Date(timeIntervalSince1970: (bucketIndex + 1) * bucketSeconds)
    }

    private nonisolated static func xDomain(points: [Point], slotCount: Int) -> ClosedRange<Double>? {
        guard !points.isEmpty else { return nil }
        // Fitted to the windows on hand; a short history sits at the trailing edge, next to now.
        let upperBound = Double(points.count) - 0.5
        let lowerBound = upperBound - Double(max(slotCount, points.count))
        return lowerBound...upperBound
    }

    private nonisolated static func axisIndexes(
        points: [Point],
        windowMinutes: Int,
        fit: PlanFitChartParts) -> [Double]
    {
        let candidateIndexes = self.axisCandidateIndexes(points: points, windowMinutes: windowMinutes)
        return self.proportionalAxisIndexes(points: points, candidateIndexes: candidateIndexes, fit: fit)
    }

    private nonisolated static func axisCandidateIndexes(points: [Point], windowMinutes: Int) -> [Int] {
        if windowMinutes <= 300 {
            return self.sessionAxisCandidateIndexes(points: points)
        }
        return points.map(\.index)
    }

    private nonisolated static func sessionAxisCandidateIndexes(points: [Point]) -> [Int] {
        guard let firstPoint = points.first else { return [] }
        let calendar = Calendar.current
        var previousPoint = firstPoint
        var rawIndexes: [Int] = [firstPoint.index]

        for point in points.dropFirst() {
            if !calendar.isDate(point.date, inSameDayAs: previousPoint.date) {
                rawIndexes.append(point.index)
            }
            previousPoint = point
        }

        return rawIndexes
    }

    private nonisolated static func proportionalAxisIndexes(
        points: [Point],
        candidateIndexes: [Int],
        fit: PlanFitChartParts) -> [Double]
    {
        guard !points.isEmpty, !candidateIndexes.isEmpty else { return [] }

        let occupiedFraction = Double(points.count) / Double(max(1, fit.slotCount))
        let proportionalBudget = Int(ceil(Double(Layout.maxAxisLabels) * occupiedFraction))
        let labelBudget = max(1, min(
            Layout.maxAxisLabels, proportionalBudget, fit.axisLabelWidthBudget, candidateIndexes.count))

        if labelBudget == 1 {
            return [Double(candidateIndexes[0])]
        }

        let step = Double(candidateIndexes.count - 1) / Double(labelBudget - 1)
        var selectedIndexes = (0..<labelBudget).map { position in
            let candidateOffset = Int((Double(position) * step).rounded())
            return candidateIndexes[candidateOffset]
        }
        selectedIndexes = Array(NSOrderedSet(array: selectedIndexes)) as? [Int] ?? selectedIndexes

        let trailingLabelCutoff = points.first!.index + Int(floor(Double(points.count) * 0.8))
        if selectedIndexes.count > 1,
           let lastSelectedIndex = selectedIndexes.last,
           lastSelectedIndex >= trailingLabelCutoff
        {
            selectedIndexes.removeLast()
        }
        selectedIndexes = PlanFitChartLayout.spacedIndexes(
            selectedIndexes, minimumSpacing: fit.axisLabelMinimumSpacing)

        if points.count == Layout.maxPoints,
           let lastVisibleIndex = points.last?.index,
           !selectedIndexes.contains(lastVisibleIndex)
        {
            selectedIndexes = PlanFitChartLayout.indexes(
                selectedIndexes, makingRoomFor: lastVisibleIndex, minimumSpacing: fit.axisLabelMinimumSpacing)
            selectedIndexes.append(lastVisibleIndex)
        }

        let deduplicated = Array(NSOrderedSet(array: selectedIndexes)) as? [Int] ?? selectedIndexes
        return deduplicated.map(Double.init)
    }

    private static func axisLabel(
        for point: Point,
        windowMinutes: Int) -> some View
    {
        ChartAxisLabelLayout.dateLabel(Text(point.date.formatted(self.axisFormat(windowMinutes: windowMinutes))))
    }

    /// Session windows reset several times a day, so their labels carry the reset hour.
    private nonisolated static func axisFormat(windowMinutes: Int) -> Date.FormatStyle {
        if windowMinutes <= 300 {
            return .dateTime.month(.abbreviated).day().hour()
        }
        return .dateTime.month(.abbreviated).day()
    }

    private nonisolated static func seriesTitle(
        name: PlanUtilizationSeriesName,
        metadata: ProviderMetadata?,
        windowMinutes: Int) -> String
    {
        switch name {
        case .antigravityGemini:
            metadata?.sessionLabel ?? "Gemini"
        case .antigravityClaudeGPT:
            metadata?.weeklyLabel ?? "Claude + GPT"
        case .session:
            localizedSessionQuotaLabel(metadata?.sessionLabel ?? "Session", windowMinutes: windowMinutes)
        case .weekly:
            L(metadata?.weeklyLabel ?? "Weekly")
        case .monthly:
            metadata?.opusLabel ?? "Monthly"
        case .opus:
            metadata?.opusLabel ?? "Opus"
        default:
            self.fallbackTitle(for: name.rawValue)
        }
    }

    private nonisolated static func fallbackTitle(for rawValue: String) -> String {
        let words = rawValue
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .split(separator: " ")
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private nonisolated static func seriesSortOrder(_ name: PlanUtilizationSeriesName) -> Int {
        switch name {
        case .session, .antigravityGemini:
            0
        case .weekly, .antigravityClaudeGPT:
            1
        case .monthly:
            2
        case .opus:
            2
        default:
            100
        }
    }

    private nonisolated static func emptyStateText(title: String?) -> String {
        if let title {
            return String(format: L("No %@ utilization data yet."), title.lowercased())
        }
        return L("No utilization data yet.")
    }

    #if DEBUG
    struct ModelSnapshot: Equatable {
        let pointCount: Int
        let axisIndexes: [Double]
        let xDomain: ClosedRange<Double>?
        let selectedSeries: String?
        let visibleSeries: [String]
        let visibleSeriesTitles: [String]
        let usedPercents: [Double]
        let pointDates: [String]
    }

    nonisolated static func _modelSnapshotForTesting(
        selectedSeriesRawValue: String? = nil,
        histories: [PlanUtilizationSeriesHistory],
        provider: UsageProvider,
        snapshot: UsageSnapshot? = nil,
        referenceDate: Date? = nil,
        width: CGFloat = 310) -> ModelSnapshot
    {
        let visibleSeries = self.visibleSeries(histories: histories, provider: provider, snapshot: snapshot)
        let selectedSeries = visibleSeries.first(where: { $0.id == selectedSeriesRawValue }) ?? visibleSeries.first
        let model = self.makeModel(
            history: selectedSeries?.history,
            provider: provider,
            referenceDate: referenceDate ?? histories.flatMap(\.entries).map(\.capturedAt).max() ?? Date(),
            width: width)
        return ModelSnapshot(
            pointCount: model.points.count,
            axisIndexes: model.axisIndexes,
            xDomain: model.xDomain,
            selectedSeries: selectedSeries?.id,
            visibleSeries: visibleSeries.map(\.id),
            visibleSeriesTitles: visibleSeries.map(\.title),
            usedPercents: model.points.map(\.usedPercent),
            pointDates: model.points.map { point in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                return formatter.string(from: point.date)
            })
    }

    nonisolated static func _detailLineForTesting(
        selectedSeriesRawValue: String? = nil,
        histories: [PlanUtilizationSeriesHistory],
        provider: UsageProvider,
        snapshot: UsageSnapshot? = nil,
        referenceDate: Date? = nil) -> String
    {
        let visibleSeries = self.visibleSeries(histories: histories, provider: provider, snapshot: snapshot)
        let selectedSeries = visibleSeries.first(where: { $0.id == selectedSeriesRawValue }) ?? visibleSeries.first
        let model = self.makeModel(
            history: selectedSeries?.history,
            provider: provider,
            referenceDate: referenceDate ?? histories.flatMap(\.entries).map(\.capturedAt).max() ?? Date(),
            width: 310)
        let window = model.points.last.flatMap { model.fit.windowsByID[$0.id] }
        return self.detailLine(
            point: model.points.last,
            windowMinutes: selectedSeries?.history.windowMinutes ?? 0,
            window: window)
    }

    nonisolated static func _axisLabelTextForTesting(
        date: Date,
        windowMinutes: Int,
        locale: Locale,
        timeZone: TimeZone) -> String
    {
        var style = self.axisFormat(windowMinutes: windowMinutes)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    nonisolated static func _emptyStateTextForTesting(title: String?) -> String {
        self.emptyStateText(title: title)
    }
    #endif

    private func xValue(for index: Int) -> PlottableValue<Double> {
        .value(L("Series"), Double(index))
    }

    @ViewBuilder
    private func utilizationChart(model: Model) -> some View {
        if let xDomain = model.xDomain {
            Chart {
                self.utilizationChartContent(model: model)
            }
            .chartXScale(domain: xDomain, range: .plotDimension(padding: ChartAxisLabelLayout.dateLabelEdgePadding))
        } else {
            Chart {
                self.utilizationChartContent(model: model)
            }
            .chartXScale(range: .plotDimension(padding: ChartAxisLabelLayout.dateLabelEdgePadding))
        }
    }

    @ChartContentBuilder
    private func utilizationChartContent(model: Model) -> some ChartContent {
        ForEach(model.points) { point in
            BarMark(
                x: self.xValue(for: point.index),
                yStart: .value(L("Capacity Start"), 0),
                yEnd: .value(L("Capacity End"), 100),
                width: .fixed(model.fit.barWidth))
                .foregroundStyle(model.trackColor)
            self.utilizationBar(point: point, model: model)
        }
        self.planFitRules(model: model)
        if let selected = self.selectedPoint(model: model) {
            RuleMark(x: self.xValue(for: selected.index))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func selectedPoint(model: Model) -> Point? {
        guard let selectedPointID else { return nil }
        return model.pointsByID[selectedPointID]
    }

    private func detailLine(model: Model, windowMinutes: Int) -> String {
        let activePoint = self.selectedPoint(model: model) ?? model.points.last
        let window = activePoint.flatMap { model.fit.windowsByID[$0.id] }
        return Self.detailLine(point: activePoint, windowMinutes: windowMinutes, window: window)
    }

    private func updateSelection(
        location: CGPoint?,
        model: Model,
        proxy: ChartProxy,
        geo: GeometryProxy)
    {
        guard let location else {
            if self.selectedPointID != nil {
                self.selectedPointID = nil
            }
            return
        }

        guard let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        guard plotFrame.contains(location) else {
            if self.selectedPointID != nil {
                self.selectedPointID = nil
            }
            return
        }

        let xInPlot = location.x - plotFrame.origin.x
        guard let xValue: Double = proxy.value(atX: xInPlot) else { return }

        var best: (id: Date, distance: Double)?
        for point in model.points {
            let distance = abs(Double(point.index) - xValue)
            if let current = best {
                if distance < current.distance {
                    best = (point.id, distance)
                }
            } else {
                best = (point.id, distance)
            }
        }

        // Stay on the last selected bar when cursor is in the gap between bars; only switch
        // selection when the cursor is over the bar's own visual body.
        if let best, let bestPoint = model.pointsByID[best.id],
           let barX = proxy.position(forX: Double(bestPoint.index))
        {
            guard ChartBarHoverSelection.accepts(
                distanceFromBarCenter: abs(location.x - (plotFrame.origin.x + barX)),
                barHalfWidth: model.fit.barWidth / 2,
                selectableCount: model.points.count)
            else { return }
        }

        if self.selectedPointID != best?.id {
            self.selectedPointID = best?.id
        }
    }
}

extension PlanUtilizationHistoryChartMenuView {
    private nonisolated static func detailLine(
        point: Point?,
        windowMinutes: Int,
        window: PlanFit.Window? = nil) -> String
    {
        guard let point else {
            return "-"
        }

        let dateLabel = self.detailDateLabel(for: point.date, windowMinutes: windowMinutes)

        let used = max(0, min(100, point.usedPercent))
        if !point.isObserved {
            return "\(dateLabel): -"
        }
        let usedText = used.formatted(.number.precision(.fractionLength(0...1)))
        let usedLine = L("%@: %@%% used", dateLabel, usedText)
        guard let window, window.isCapped else { return usedLine }
        return "\(usedLine) · \(PlanFitPresentation.cappedHoursText(window.cappedHours))"
    }

    private nonisolated static func detailDateLabel(for date: Date, windowMinutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = codexBarLocalizedLocale()
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate("MMM d, h:mm a")
        var rendered = formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
        let amSymbol = formatter.amSymbol ?? ""
        let pmSymbol = formatter.pmSymbol ?? ""
        if !amSymbol.isEmpty {
            rendered = rendered.replacingOccurrences(of: amSymbol, with: amSymbol.lowercased())
        }
        if !pmSymbol.isEmpty {
            rendered = rendered.replacingOccurrences(of: pmSymbol, with: pmSymbol.lowercased())
        }
        return rendered
    }
}

// MARK: - Plan fit

extension PlanUtilizationHistoryChartMenuView {
    private var showsPlanFit: Bool {
        self.visibleSeries.contains { $0.history.windowMinutes > 0 && !$0.history.name.isQuotaObservation }
    }

    /// The summary and verdict lines are reserved for every series so the measured menu height stays fixed.
    private var planFitFooterHeight: CGFloat {
        self.showsPlanFit ? 2 * (PlanFitChartLayout.footerSpacing + PlanFitChartLayout.footerLineHeight) : 0
    }

    private func chartFooter(model: Model, windowMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: PlanFitChartLayout.footerSpacing) {
            Text(self.detailLine(model: model, windowMinutes: windowMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: Layout.detailHeight, alignment: .leading)
            if self.showsPlanFit {
                Text(model.fit.summary.flatMap { PlanFitPresentation.summaryLine($0) } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .frame(height: PlanFitChartLayout.footerLineHeight, alignment: .leading)
                Text(model.fit.summary.map { PlanFitPresentation.verdictLine($0.verdict) } ?? "")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .frame(height: PlanFitChartLayout.footerLineHeight, alignment: .leading)
            }
        }
    }

    private static func percentAxisMarks() -> some AxisContent {
        AxisMarks(position: .leading, values: PlanFitChartLayout.yAxisTicks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color(nsColor: .separatorColor))
            AxisTick().foregroundStyle(Color.clear)
            AxisValueLabel(centered: false) {
                if let raw = value.as(Double.self) {
                    Text(PlanFitPresentation.percentAxisLabel(raw))
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
    }

    /// Capped windows take the capped color; the window still in progress is drawn lighter, as "so far".
    @ChartContentBuilder
    private func utilizationBar(point: Point, model: Model) -> some ChartContent {
        let bar = BarMark(
            x: self.xValue(for: point.index),
            yStart: .value(L("Utilization Start"), 0),
            yEnd: .value(L("Utilization End"), point.usedPercent),
            width: .fixed(model.fit.barWidth))
            .foregroundStyle(Self.barColor(for: point, model: model))
        if let label = model.fit.cappedLabelsByIndex[point.index] {
            bar.annotation(position: .top, alignment: .center, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        } else {
            bar
        }
    }

    /// A solid rule at the cap and a dashed reference rule at the median peak.
    @ChartContentBuilder
    private func planFitRules(model: Model) -> some ChartContent {
        RuleMark(y: .value(L("Limit"), PlanFit.cappedPercent))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .lineStyle(StrokeStyle(lineWidth: 1))
        if let median = model.fit.summary?.medianPeakPercent {
            RuleMark(y: .value(L("Median"), median))
                .foregroundStyle(ChartReferenceLine.color)
                .lineStyle(ChartReferenceLine.strokeStyle)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(PlanFitPresentation.medianText(median))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private static func barColor(for point: Point, model: Model) -> Color {
        guard let window = model.fit.windowsByID[point.id] else { return model.barColor }
        let color = window.isCapped ? model.fit.cappedColor : model.barColor
        return window.isCurrent ? color.opacity(PlanFitChartLayout.currentWindowOpacity) : color
    }

    private nonisolated static func planFitParts(
        history: PlanUtilizationSeriesHistory?,
        points: [Point],
        accent: ProviderColor,
        referenceDate: Date,
        width: CGFloat) -> PlanFitChartParts
    {
        let windowMinutes = history?.windowMinutes ?? 0
        let inputs = history.map { self.planFitWindowInputs(history: $0, points: points) } ?? []
        var summary: PlanFit.Summary?
        if let history, history.windowMinutes > 0, !history.name.isQuotaObservation {
            summary = PlanFit.summary(
                windows: inputs.map(\.input),
                windowMinutes: history.windowMinutes,
                now: referenceDate)
        }
        var windowsByID: [Date: PlanFit.Window] = [:]
        for (input, window) in zip(inputs, summary?.windows ?? []) {
            windowsByID[input.id] = window
        }

        let plotWidth = PlanFitChartLayout.plotWidth(menuWidth: width)
        let slotCount = PlanFitChartLayout.slotCount(pointCount: points.count)
        var cappedHoursByIndex: [Int: Double] = [:]
        for point in points {
            if let window = windowsByID[point.id], window.isCapped {
                cappedHoursByIndex[point.index] = window.cappedHours
            }
        }
        var cappedLabelsByIndex: [Int: String] = [:]
        let labeledIndexes = PlanFitChartLayout.labeledCappedIndexes(
            Array(cappedHoursByIndex.keys),
            slotWidth: plotWidth / CGFloat(slotCount))
        for index in labeledIndexes {
            if let hours = cappedHoursByIndex[index] {
                cappedLabelsByIndex[index] = PlanFitPresentation.cappedBarLabel(hours: hours)
            }
        }

        let labelWidth = PlanFitChartLayout.axisLabelWidth(windowMinutes: windowMinutes)
        return PlanFitChartParts(
            slotCount: slotCount,
            barWidth: PlanFitChartLayout.barWidth(slotCount: slotCount, plotWidth: plotWidth, minimum: Layout.barWidth),
            cappedColor: ChartPalette.color(for: PlanFitPresentation.cappedSlot(accent: accent)),
            summary: summary,
            windowsByID: windowsByID,
            cappedLabelsByIndex: cappedLabelsByIndex,
            axisLabelWidthBudget: PlanFitChartLayout.axisLabelWidthBudget(
                plotWidth: plotWidth,
                labelWidth: labelWidth),
            axisLabelMinimumSpacing: PlanFitChartLayout.axisLabelMinimumSpacing(
                slotCount: slotCount,
                plotWidth: plotWidth,
                labelWidth: labelWidth))
    }

    private struct PlanFitWindowInput {
        /// The chart point id, which is the window's period boundary.
        let id: Date
        let input: PlanFit.WindowInput
    }

    /// Groups the history's captures into the chart's observed windows, reusing the bars' period boundaries.
    private nonisolated static func planFitWindowInputs(
        history: PlanUtilizationSeriesHistory,
        points: [Point]) -> [PlanFitWindowInput]
    {
        guard history.windowMinutes > 0, !history.name.isQuotaObservation else { return [] }
        let observedPoints = points.filter(\.isObserved)
        let observedIDs = Set(observedPoints.map(\.id))
        guard !observedIDs.isEmpty else { return [] }
        let lattice = self.resetBoundaryLattice(entries: history.entries, windowMinutes: history.windowMinutes)
        var capturesByID: [Date: [PlanFit.Capture]] = [:]
        for entry in history.entries {
            let candidate = self.observedPointCandidate(
                for: entry,
                windowMinutes: history.windowMinutes,
                resetBoundaryLattice: lattice)
            guard observedIDs.contains(candidate.effectiveBoundaryDate) else { continue }
            capturesByID[candidate.effectiveBoundaryDate, default: []].append(PlanFit.Capture(
                capturedAt: entry.capturedAt,
                usedPercent: candidate.usedPercent))
        }
        return observedPoints.map { point in
            PlanFitWindowInput(
                id: point.id,
                input: PlanFit.WindowInput(resetsAt: point.date, captures: capturesByID[point.id] ?? []))
        }
    }

    #if DEBUG
    struct PlanFitSnapshot: Equatable {
        let slotCount: Int
        let barWidth: CGFloat
        let xDomain: ClosedRange<Double>?
        let cappedIndexes: [Int]
        let currentIndexes: [Int]
        let cappedLabels: [Int: String]
        let summary: PlanFit.Summary?
        let summaryLine: String?
        let verdictLine: String?
    }

    nonisolated static func _planFitSnapshotForTesting(
        selectedSeriesRawValue: String? = nil,
        histories: [PlanUtilizationSeriesHistory],
        provider: UsageProvider,
        snapshot: UsageSnapshot? = nil,
        referenceDate: Date,
        width: CGFloat = 310) -> PlanFitSnapshot
    {
        let visibleSeries = self.visibleSeries(histories: histories, provider: provider, snapshot: snapshot)
        let selectedSeries = visibleSeries.first(where: { $0.id == selectedSeriesRawValue }) ?? visibleSeries.first
        let model = self.makeModel(
            history: selectedSeries?.history,
            provider: provider,
            referenceDate: referenceDate,
            width: width)
        let fit = model.fit
        return PlanFitSnapshot(
            slotCount: fit.slotCount,
            barWidth: fit.barWidth,
            xDomain: model.xDomain,
            cappedIndexes: model.points.filter { fit.windowsByID[$0.id]?.isCapped == true }.map(\.index),
            currentIndexes: model.points.filter { fit.windowsByID[$0.id]?.isCurrent == true }.map(\.index),
            cappedLabels: fit.cappedLabelsByIndex,
            summary: fit.summary,
            summaryLine: fit.summary.flatMap { PlanFitPresentation.summaryLine($0) },
            verdictLine: fit.summary.map { PlanFitPresentation.verdictLine($0.verdict) })
    }
    #endif
}
