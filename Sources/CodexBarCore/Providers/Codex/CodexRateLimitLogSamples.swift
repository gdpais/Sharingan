import Foundation

// MARK: - Codex rate-limit log samples

// Kept outside Vendored/CostUsage on purpose: files there feed `CodexParserHash`, and changing that hash would rebuild
// every user's cost store although this reader neither changes cost parsing nor persists anything.

/// One quota window from the `rate_limits` field of a Codex rollout `token_count` event.
///
/// Codex persists `EventMsg::TokenCount { info, rate_limits }` verbatim in its rollout JSONL. The snapshot is the
/// snake_case form of the `RateLimitSnapshot` the app-server returns as `rateLimits` (see `RPCRateLimitSnapshot`):
/// each window carries `used_percent`, `window_minutes`, and either `resets_at` (Unix seconds, current CLI builds) or
/// `resets_in_seconds` (relative to the event, older CLI builds).
public struct CodexRateLimitLogWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

/// The default (`codex`) quota snapshot one rollout `token_count` event observed.
public struct CodexRateLimitLogSample: Equatable, Sendable {
    /// Envelope timestamp of the `token_count` event.
    public let observedAt: Date
    public let primary: CodexRateLimitLogWindow?
    public let secondary: CodexRateLimitLogWindow?
    /// Trimmed, lowercased `session_meta.creator_account_id` of the rollout, when Codex recorded one.
    public let creatorAccountID: String?

    public init(
        observedAt: Date,
        primary: CodexRateLimitLogWindow?,
        secondary: CodexRateLimitLogWindow?,
        creatorAccountID: String? = nil)
    {
        self.observedAt = observedAt
        self.primary = primary
        self.secondary = secondary
        self.creatorAccountID = creatorAccountID
    }

    public var windows: [CodexRateLimitLogWindow] {
        [self.primary, self.secondary].compactMap(\.self)
    }

    func attributed(toCreatorAccountID creatorAccountID: String?) -> Self {
        Self(
            observedAt: self.observedAt,
            primary: self.primary,
            secondary: self.secondary,
            creatorAccountID: creatorAccountID)
    }
}

/// Rate-limit samples read from local Codex rollouts, oldest first.
public struct CodexRateLimitLogScan: Equatable, Sendable {
    public let samples: [CodexRateLimitLogSample]
    /// False when a rollout could not be read to its end; callers must not advance a resume watermark.
    public let isComplete: Bool

    public init(samples: [CodexRateLimitLogSample], isComplete: Bool) {
        self.samples = samples
        self.isComplete = isComplete
    }

    public static let empty = Self(samples: [], isComplete: true)
}

public enum CodexRateLimitLogScanner {
    /// Reads `rate_limits` samples from the rollouts of one Codex home (`sessions` and `archived_sessions`).
    ///
    /// - Parameters:
    ///   - codexHomePath: Managed/profile Codex home; nil resolves `CODEX_HOME` or `~/.codex` like the cost scanner.
    ///   - modifiedSince: Skips rollouts last modified before this instant (an earlier pass already read them).
    ///   - horizon: Ignores events older than this instant and date partitions before it.
    public static func scan(
        codexHomePath: String?,
        modifiedSince: Date?,
        horizon: Date,
        now: Date = Date()) -> CodexRateLimitLogScan
    {
        var options = CostUsageScanner.Options()
        if let home = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            options.codexSessionsRoot = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        } else if TestProcessSafety.isRunning {
            // Tests pass explicit roots; never read the real ~/.codex from a test process.
            return .empty
        }
        return CostUsageScanner.codexRateLimitSamples(
            roots: CostUsageScanner.codexSessionsRoots(options: options),
            modifiedSince: modifiedSince,
            horizon: horizon,
            now: now,
            calendar: options.calendar)
    }
}

extension CostUsageScanner {
    private struct CodexRateLimitLineFields {
        let timestamp: String
        let rateLimits: Data
    }

    private struct CodexRateLimitSessionMeta {
        let creatorAccountID: String?
    }

    private static let codexRateLimitFieldType = Array("type".utf8)
    private static let codexRateLimitFieldTimestamp = Array("timestamp".utf8)
    private static let codexRateLimitFieldPayload = Array("payload".utf8)
    private static let codexRateLimitFieldRateLimits = Array("rate_limits".utf8)
    /// Codex names the account-wide quota `codex`; other ids are model-specific limits (e.g. `codex_bengalfox`).
    private static let codexDefaultRateLimitID = "codex"
    /// A reset further out than the window itself (plus slack) is not a plausible boundary for that window.
    private static let codexRateLimitResetSlackSeconds: TimeInterval = 60 * 60
    /// Bounds the minutes conversion; real Codex windows are at most a 30-day (43,200-minute) cycle.
    private static let codexRateLimitMaxWindowMinutes: Double = 366 * 24 * 60

    static func codexRateLimitSamples(
        roots: [URL],
        modifiedSince: Date?,
        horizon: Date,
        now: Date,
        calendar: Calendar = .current,
        checkCancellation: CancellationCheck? = nil) -> CodexRateLimitLogScan
    {
        let range = CostUsageDayRange(since: horizon, until: now, calendar: calendar)
        var seenPaths: Set<String> = []
        var files: [URL] = []
        for root in roots {
            let rootFiles = Self.listCodexSessionFiles(
                root: root,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey,
                includeRecursive: false,
                calendar: calendar)
            for file in rootFiles where seenPaths.insert(Self.codexPathKey(file)).inserted {
                files.append(file)
            }
        }

        var samples: [CodexRateLimitLogSample] = []
        var isComplete = true
        for file in files.sorted(by: { $0.path < $1.path }) {
            if let modifiedSince, let modifiedAt = Self.codexRateLimitFileModifiedAt(file), modifiedAt < modifiedSince {
                continue
            }
            do {
                let fileSamples = try Self.codexRateLimitSamples(
                    fileURL: file,
                    horizon: horizon,
                    checkCancellation: checkCancellation)
                samples.append(contentsOf: fileSamples)
            } catch is CancellationError {
                return CodexRateLimitLogScan(samples: [], isComplete: false)
            } catch {
                isComplete = false
            }
        }
        samples.sort { $0.observedAt < $1.observedAt }
        return CodexRateLimitLogScan(samples: samples, isComplete: isComplete)
    }

    static func codexRateLimitSamples(
        fileURL: URL,
        horizon: Date,
        checkCancellation: CancellationCheck? = nil) throws -> [CodexRateLimitLogSample]
    {
        var creatorAccountID: String?
        var sawSessionMeta = false
        var samples: [CodexRateLimitLogSample] = []
        try CostUsageJsonl.scan(
            fileURL: fileURL,
            maxLineBytes: Self.codexSessionMetadataMaxLineBytes,
            prefixBytes: Self.codexSessionMetadataMaxLineBytes,
            checkCancellation: checkCancellation,
            onLine: { line in
                guard !line.wasTruncated, !line.bytes.isEmpty else { return }
                // The first (leaf) session_meta owns the rollout; copied ancestor metadata never reassigns it.
                if !sawSessionMeta,
                   line.bytes.containsAscii(#""session_meta""#),
                   let metadata = Self.codexRateLimitSessionMeta(fromLine: line.bytes)
                {
                    sawSessionMeta = true
                    creatorAccountID = metadata.creatorAccountID
                    return
                }
                guard line.bytes.containsAscii(#""rate_limits""#),
                      let sample = Self.codexRateLimitSample(fromLine: line.bytes),
                      sample.observedAt >= horizon
                else { return }
                Self.appendCodexRateLimitSample(sample, to: &samples)
            })
        return samples.map { $0.attributed(toCreatorAccountID: creatorAccountID) }
    }

    /// Decodes the `rate_limits` snapshot of one rollout line, or nil for any other line.
    static func codexRateLimitSample(fromLine bytes: Data) -> CodexRateLimitLogSample? {
        guard let fields = Self.codexRateLimitLineFields(bytes),
              let observedAt = Self.dateFromTimestamp(fields.timestamp)
        else { return nil }
        return autoreleasepool {
            guard let rateLimits = (try? JSONSerialization.jsonObject(with: fields.rateLimits)) as? [String: Any]
            else { return nil }
            return Self.codexRateLimitSample(rateLimits: rateLimits, observedAt: observedAt)
        }
    }

    static func codexRateLimitSample(rateLimits: [String: Any], observedAt: Date) -> CodexRateLimitLogSample? {
        if let limitID = rateLimits["limit_id"] as? String {
            let normalized = limitID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.isEmpty || normalized == Self.codexDefaultRateLimitID else { return nil }
        }
        let primary = Self.codexRateLimitWindow(rateLimits["primary"], observedAt: observedAt)
        let secondary = Self.codexRateLimitWindow(rateLimits["secondary"], observedAt: observedAt)
        guard primary != nil || secondary != nil else { return nil }
        return CodexRateLimitLogSample(observedAt: observedAt, primary: primary, secondary: secondary)
    }

    static func codexRateLimitWindow(_ value: Any?, observedAt: Date) -> CodexRateLimitLogWindow? {
        guard let window = value as? [String: Any],
              let usedPercent = Self.codexRateLimitFiniteNumber(window["used_percent"])
        else { return nil }
        let windowMinutes = Self.codexRateLimitFiniteNumber(window["window_minutes"])
            .flatMap { $0 >= 1 && $0 <= Self.codexRateLimitMaxWindowMinutes ? Int($0) : nil }
        let resetsAt = Self.codexRateLimitResetDate(window, observedAt: observedAt)
        if let resetsAt {
            // A boundary at or before the event means the reading belongs to a window that already rolled over,
            // which is what fork children re-emit when they copy ancestor token_count rows with fresh timestamps.
            guard resetsAt > observedAt else { return nil }
            if let windowMinutes {
                let latestPlausibleReset = observedAt.addingTimeInterval(
                    TimeInterval(windowMinutes) * 60 + Self.codexRateLimitResetSlackSeconds)
                guard resetsAt <= latestPlausibleReset else { return nil }
            }
        }
        return CodexRateLimitLogWindow(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    /// Current CLI builds log `resets_at` (Unix seconds); older ones logged `resets_in_seconds` from the event.
    private static func codexRateLimitResetDate(_ window: [String: Any], observedAt: Date) -> Date? {
        if let epochSeconds = Self.codexRateLimitFiniteNumber(window["resets_at"]), epochSeconds > 0 {
            return Date(timeIntervalSince1970: epochSeconds)
        }
        if let secondsToReset = Self.codexRateLimitFiniteNumber(window["resets_in_seconds"]), secondsToReset >= 0 {
            return observedAt.addingTimeInterval(secondsToReset)
        }
        return nil
    }

    private static func codexRateLimitFiniteNumber(_ value: Any?) -> Double? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { return nil }
        return number
    }

    static func normalizedCodexCreatorAccountID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    /// Locates the envelope timestamp and the `payload.rate_limits` object with the scanner's byte-level field
    /// readers, so only that small object goes through `JSONSerialization`.
    private static func codexRateLimitLineFields(_ bytes: Data) -> CodexRateLimitLineFields? {
        bytes.withUnsafeBytes { rawBytes in
            let buffer = rawBytes.bindMemory(to: UInt8.self)
            let root = 0..<buffer.count
            func string(_ field: [UInt8], in range: Range<Int>) -> String? {
                Self.extractJSONByteStringField(field, from: buffer, in: range, atDepth: 1)
            }
            func object(_ field: [UInt8], in range: Range<Int>) -> Range<Int>? {
                Self.extractJSONByteObjectField(field, from: buffer, in: range, atDepth: 1)
            }
            guard string(Self.codexRateLimitFieldType, in: root) == "event_msg",
                  let timestamp = string(Self.codexRateLimitFieldTimestamp, in: root),
                  let payload = object(Self.codexRateLimitFieldPayload, in: root),
                  string(Self.codexRateLimitFieldType, in: payload) == "token_count",
                  let rateLimits = object(Self.codexRateLimitFieldRateLimits, in: payload)
            else { return nil }
            return CodexRateLimitLineFields(timestamp: timestamp, rateLimits: Data(buffer[rateLimits]))
        }
    }

    private static func codexRateLimitFileModifiedAt(_ fileURL: URL) -> Date? {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func codexRateLimitSessionMeta(fromLine bytes: Data) -> CodexRateLimitSessionMeta? {
        autoreleasepool {
            guard let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
                  object["type"] as? String == "session_meta"
            else { return nil }
            let payload = object["payload"] as? [String: Any]
            return CodexRateLimitSessionMeta(
                creatorAccountID: Self.normalizedCodexCreatorAccountID(payload?["creator_account_id"] as? String))
        }
    }

    /// Codex logs one `token_count` per model response, so identical consecutive readings are common. Within one
    /// clock hour they carry no extra peak information; keeping only the latest bounds memory for large corpora.
    private static func appendCodexRateLimitSample(
        _ sample: CodexRateLimitLogSample,
        to samples: inout [CodexRateLimitLogSample])
    {
        if let last = samples.last,
           last.primary == sample.primary,
           last.secondary == sample.secondary,
           last.observedAt <= sample.observedAt,
           Self.codexRateLimitHourBucket(last.observedAt) == Self.codexRateLimitHourBucket(sample.observedAt)
        {
            samples[samples.count - 1] = sample
            return
        }
        samples.append(sample)
    }

    /// Same hourly bucket as plan-utilization history (`UsageStore.planUtilizationHourBucket`).
    private static func codexRateLimitHourBucket(_ date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / 3600))
    }
}
