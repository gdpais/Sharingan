import Foundation
import SharinganCore

extension Notification.Name {
    static let sharinganDebugBlinkNow = Notification.Name("sharinganDebugBlinkNow")
    #if DEBUG
    static let sharinganDebugSimulateMemoryPressure =
        Notification.Name("\(AppIdentity.reverseDNS).debug.simulateMemoryPressure")
    #endif
    static let sharinganSessionLimitReset = Notification.Name("sharinganSessionLimitReset")
    static let sharinganWeeklyLimitReset = Notification.Name("sharinganWeeklyLimitReset")
    static let sharinganProviderConfigDidChange = Notification.Name("sharinganProviderConfigDidChange")
    static let sharinganLocalConfigFileDidChange = Notification.Name("sharinganLocalConfigFileDidChange")
    static let sharinganUsageSnapshotsDidChange = Notification.Name("sharinganUsageSnapshotsDidChange")
    static let sharinganQuotaWarningDidPost = Notification.Name("sharinganQuotaWarningDidPost")
}

final class UsageSnapshotsDidChangeEvent: NSObject, @unchecked Sendable {
    let snapshots: [AccountSnapshotSyncPayload]

    init(snapshots: [AccountSnapshotSyncPayload]) {
        self.snapshots = snapshots
    }
}

@MainActor
final class SessionLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class WeeklyLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class QuotaWarningPostedEvent: NSObject {
    let provider: UsageProvider
    let window: QuotaWarningWindow
    let threshold: Int
    let postedAt: Date

    init(provider: UsageProvider, window: QuotaWarningWindow, threshold: Int, postedAt: Date) {
        self.provider = provider
        self.window = window
        self.threshold = threshold
        self.postedAt = postedAt
    }
}
