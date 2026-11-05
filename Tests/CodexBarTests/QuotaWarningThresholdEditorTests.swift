import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct QuotaWarningThresholdEditorTests {
    @Test
    func `draft shows every configured threshold highest first`() {
        let draft = QuotaWarningThresholdEditorText.Draft(thresholds: [5, 80, 20, 50, 35, 65, 10])

        #expect(draft.texts == ["80", "65", "50", "35", "20", "10", "5"])
        #expect(draft.count == 7)
        #expect(draft.isDirty == false)
    }

    @Test
    func `untouched draft of a long list never writes`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [90, 70, 50, 30, 20, 10, 5])

        #expect(draft.takeResolvedThresholds() == nil)
        #expect(draft.texts.count == 7)
    }

    @Test
    func `editing one field of a long list keeps the others`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [90, 70, 50, 30, 20, 10, 5])

        draft.setText("40", at: 3)

        #expect(draft.takeResolvedThresholds() == [90, 70, 50, 40, 20, 10, 5])
        #expect(draft.texts == ["90", "70", "50", "40", "20", "10", "5"])
    }

    @Test
    func `commit sorts and de-duplicates typed thresholds`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [50, 20])

        draft.setText("20", at: 0)
        #expect(draft.takeResolvedThresholds() == [20])

        draft.setText("75", at: 0)
        #expect(draft.takeResolvedThresholds() == [75])

        var unsorted = QuotaWarningThresholdEditorText.Draft(thresholds: [50, 20])
        unsorted.setText("5", at: 0)
        unsorted.setText("60", at: 1)
        #expect(unsorted.takeResolvedThresholds() == [60, 5])
        #expect(unsorted.texts == ["60", "5"])
    }

    @Test
    func `adding offers a deeper threshold and sorts it into place`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [50, 20])

        #expect(draft.canAddThreshold)
        draft.addThreshold()
        #expect(draft.texts == ["50", "20", "10"])
        #expect(draft.takeResolvedThresholds() == [50, 20, 10])
    }

    @Test
    func `adding stops at the editor cap`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [50, 20])
        while draft.canAddThreshold {
            draft.addThreshold()
        }

        #expect(draft.count == QuotaWarningThresholds.editorMaximumCount)
        #expect(draft.takeResolvedThresholds() == [50, 20, 10, 5, 2])

        draft.addThreshold()
        #expect(draft.count == QuotaWarningThresholds.editorMaximumCount)
    }

    @Test
    func `a list beyond the cap stays editable but cannot grow`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [90, 80, 70, 60, 50, 40])

        #expect(draft.canAddThreshold == false)
        #expect(draft.canRemoveThreshold)
        draft.removeLastThreshold()
        #expect(draft.takeResolvedThresholds() == [90, 80, 70, 60, 50])
        #expect(draft.canAddThreshold == false)
    }

    @Test
    func `removing drops the lowest threshold but keeps at least one`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [80, 50, 20])

        draft.removeLastThreshold()
        #expect(draft.takeResolvedThresholds() == [80, 50])

        draft.removeThreshold(at: 0)
        #expect(draft.takeResolvedThresholds() == [50])
        #expect(draft.canRemoveThreshold == false)

        draft.removeLastThreshold()
        #expect(draft.texts == ["50"])
        #expect(draft.takeResolvedThresholds() == nil)
    }

    @Test
    func `out of range edits are ignored`() {
        var draft = QuotaWarningThresholdEditorText.Draft(thresholds: [50, 20])

        draft.setText("10", at: 5)
        draft.removeThreshold(at: 9)

        #expect(draft.text(at: 5).isEmpty)
        #expect(draft.isDirty == false)
    }

    @Test
    func `only the first two fields carry semantic labels`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(QuotaWarningThresholdEditorText.label(at: 0) == "Warning")
            #expect(QuotaWarningThresholdEditorText.label(at: 1) == "Critical")
            #expect(QuotaWarningThresholdEditorText.label(at: 2) == nil)
        }
        #expect(QuotaWarningThresholdEditorText.placeholder(at: 0) == "50")
        #expect(QuotaWarningThresholdEditorText.placeholder(at: 3).isEmpty)
    }

    @Test
    func `suggested additions fill the deepest gap first`() {
        #expect(QuotaWarningThresholds.suggestedAddition(to: [50, 20]) == 10)
        #expect(QuotaWarningThresholds.suggestedAddition(to: [50, 25]) == 12)
        #expect(QuotaWarningThresholds.suggestedAddition(to: [1]) == 50)
        #expect(QuotaWarningThresholds.suggestedAddition(to: [0]) == 50)
        #expect(QuotaWarningThresholds.suggestedAddition(to: [50, 2, 1]) == 75)
        #expect(QuotaWarningThresholds.suggestedAddition(to: Array(1...99)) == nil)
    }

    @Test
    func `resolved entries drop blanks clamp and sort`() {
        #expect(QuotaWarningThresholds.resolved(entries: [nil, 12, nil]) == [12])
        #expect(QuotaWarningThresholds.resolved(entries: [nil, nil]) == QuotaWarningThresholds.defaults)
        #expect(QuotaWarningThresholds.resolved(entries: [120, 30, 30, -1]) == [99, 30, 0])
    }

    @Test
    func `lane overrides share the window config shape`() throws {
        var config = QuotaWarningConfig()
        #expect(config.isEmpty)

        config.setLaneConfig(QuotaWarningWindowConfig(thresholds: [70, 40, 10]), for: QuotaWarningLaneID.tertiary)
        #expect(!config.isEmpty)
        #expect(config.laneOverrideIDs == ["tertiary"])
        #expect(config.thresholds(forLane: "tertiary", fallback: [50, 20]) == [70, 40, 10])
        #expect(config.thresholds(forLane: "fictional-extra", fallback: [50, 20]) == [50, 20])
        #expect(config.isEnabled(forLane: "tertiary", fallback: false))
        #expect(config.isEnabled(forLane: "fictional-extra", fallback: false) == false)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(QuotaWarningConfig.self, from: data)
        #expect(decoded == config)

        config.setLaneConfig(QuotaWarningWindowConfig(), for: QuotaWarningLaneID.tertiary)
        #expect(config.windows == nil)
        #expect(config.isEmpty)
    }

    @Test
    func `configs without lanes encode and decode unchanged`() throws {
        let config = QuotaWarningConfig(session: QuotaWarningWindowConfig(thresholds: [80, 50, 30, 10]))
        let json = try #require(String(data: JSONEncoder().encode(config), encoding: .utf8))
        #expect(!json.contains("windows"))

        let legacy = Data(#"{"weekly":{"thresholds":[90,60,30,15,5],"enabled":true}}"#.utf8)
        let decoded = try JSONDecoder().decode(QuotaWarningConfig.self, from: legacy)
        #expect(decoded.windows == nil)
        #expect(decoded.thresholds(for: .weekly, global: [50, 20]) == [90, 60, 30, 15, 5])
    }
}
