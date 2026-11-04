import CodexBarCore
import Foundation

extension UsageMenuCardView.Model {
    /// Email redaction for chart spec v2 text: series names, their point labels, and reference labels.
    static func redactedChartText(_ text: String) -> String {
        PersonalInfoRedactor.redactEmails(in: text, isEnabled: true) ?? text
    }
}
