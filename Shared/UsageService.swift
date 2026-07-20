import Foundation
import Darwin

struct UsageWindow: Codable, Hashable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Int?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

/// Canonical quota slots used by the UI. The API field names are not stable:
/// after the July 2026 change the seven-day window can arrive as
/// `primary_window` with no `secondary_window`. Classify by the window itself
/// so a server-side layout change cannot turn a weekly quota into a 5-hour one.
struct ClassifiedUsageWindows {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
}

enum UsageWindowClassifier {
    struct Candidate {
        let sourceKey: String
        let window: UsageWindow
    }

    private enum Kind { case fiveHour, weekly }

    static func classify(_ candidates: [Candidate]) -> ClassifiedUsageWindows {
        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        var unresolved: [Candidate] = []

        for candidate in candidates {
            switch kind(for: candidate.window) {
            case .fiveHour?:
                fiveHour = preferred(fiveHour, candidate.window, targetSeconds: 18_000)
            case .weekly?:
                weekly = preferred(weekly, candidate.window, targetSeconds: 604_800)
            case nil:
                unresolved.append(candidate)
            }
        }

        // Compatibility fallback for old payloads that omit the duration.
        // We only use the field name when it is unambiguous; a lone unknown
        // `primary_window` is deliberately not labelled as 5-hour, because the
        // current API also uses that key for the weekly quota.
        for candidate in unresolved {
            if candidate.sourceKey == "secondary_window", weekly == nil {
                weekly = candidate.window
            } else if candidates.count > 1,
                      candidate.sourceKey == "primary_window", fiveHour == nil {
                fiveHour = candidate.window
            }
        }

        return ClassifiedUsageWindows(fiveHour: fiveHour, weekly: weekly)
    }

    private static func kind(for window: UsageWindow) -> Kind? {
        guard let seconds = window.windowSeconds, seconds > 0 else { return nil }
        // Codex has historically used 5 hours and 7 days. Keeping a wide gap
        // between the buckets tolerates modest server-side duration changes,
        // while still refusing to guess for an unknown future quota type.
        if seconds <= 24 * 60 * 60 { return .fiveHour }
        if seconds >= 3 * 24 * 60 * 60, seconds <= 14 * 24 * 60 * 60 { return .weekly }
        return nil
    }

    private static func preferred(_ current: UsageWindow?, _ incoming: UsageWindow,
                                  targetSeconds: Int) -> UsageWindow {
        guard let current else { return incoming }
        let currentDistance = abs((current.windowSeconds ?? targetSeconds) - targetSeconds)
        let incomingDistance = abs((incoming.windowSeconds ?? targetSeconds) - targetSeconds)
        return incomingDistance < currentDistance ? incoming : current
    }
}

struct UsageSnapshot: Codable, Hashable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let plan: String?
    let updatedAt: Date
    let errorMessage: String?
    let activity: [TokenActivityDay]?
    let tokenStats: TokenStats?
    let resetCreditsRemaining: Int64?

    static let placeholder = UsageSnapshot(
        primary: UsageWindow(usedPercent: 38, resetAt: Date().addingTimeInterval(3.5 * 3600), windowSeconds: 18_000),
        secondary: UsageWindow(usedPercent: 13, resetAt: Date().addingTimeInterval(6.9 * 86_400), windowSeconds: 604_800),
        plan: "Codex",
        updatedAt: Date(),
        errorMessage: nil,
        activity: TokenActivityDay.placeholder,
        tokenStats: TokenStats.placeholder,
        resetCreditsRemaining: 2
    )
}

struct TokenStats: Codable, Hashable {
    let cumulativeTokens: Int64
    let peakDailyTokens: Int64
    let longestTaskSeconds: Int64
    let currentStreak: Int
    let longestStreak: Int

    static let placeholder = TokenStats(cumulativeTokens: 690_000_000, peakDailyTokens: 120_000_000,
                                        longestTaskSeconds: 5_040, currentStreak: 3, longestStreak: 5)
}

struct TokenActivityDay: Codable, Hashable, Identifiable {
    let day: String
    let tokens: Int64
    var id: String { day }

    static var placeholder: [TokenActivityDay] {
        let calendar = Calendar.current
        return (0..<364).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            return TokenActivityDay(day: Self.keyFormatter.string(from: date),
                                    tokens: offset < 18 ? Int64((18 - offset) * 740_000) : 0)
        }
    }

    static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum UsageServiceError: LocalizedError {
    case missingAuth
    case invalidAuth
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .missingAuth: return "未找到 Codex 登录信息"
        case .invalidAuth: return "Codex 登录信息已失效"
        case .invalidResponse: return "用量数据格式暂不受支持"
        case .server(let code): return "服务返回错误（\(code)）"
        }
    }
}

actor UsageService {
    static let shared = UsageService()
    private let userHome: URL = {
        if let record = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: record.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    private var isWidget: Bool { Bundle.main.bundleIdentifier?.contains(".widget") == true }
    private var officialUsageCache: (date: Date, activity: [TokenActivityDay], stats: TokenStats, resetCredits: Int64?)?
    private lazy var cacheURL = userHome
        .appendingPathComponent("Library/Caches/com.codexmeter.shared/usage.json")
    private lazy var pendingRollbackURL = userHome
        .appendingPathComponent("Library/Caches/com.codexmeter.shared/pending-rollbacks.json")

    private struct PendingRollback: Codable {
        let usedPercent: Double
        let resetAt: Date?
        let windowSeconds: Int?
        let firstSeenAt: Date
        var confirmations: Int
    }

    private struct PendingRollbackState: Codable {
        var primary: PendingRollback?
        var secondary: PendingRollback?
    }

    func fetch() async -> UsageSnapshot {
        // The host app owns credentials and networking. The widget can read
        // only this sanitized snapshot through its narrow sandbox exception.
        if isWidget {
            return loadCache() ?? UsageSnapshot(primary: nil, secondary: nil, plan: nil,
                                                updatedAt: Date(), errorMessage: "请打开 CodexMeter 完成首次同步", activity: nil,
                                                tokenStats: nil, resetCreditsRemaining: nil)
        }
        do {
            let auth = try loadAuth()
            var components = URLComponents(string: "https://chatgpt.com/backend-api/wham/usage")!
            components.queryItems = [URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970)))]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            request.timeoutInterval = 15
            request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(auth.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue("CodexMeter/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (data, response) = try await configuredSession().data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 { throw UsageServiceError.invalidAuth }
                throw UsageServiceError.server(http.statusCode)
            }

            let decoded = try decodeUsage(data)
            let previous = loadCache()
            let official = loadOfficialTokenUsage()
            let resetCreditWasUsed: Bool = {
                guard let old = previous?.resetCreditsRemaining, let new = official?.resetCredits else { return false }
                return new < old
            }()
            var pending = loadPendingRollbacks()
            let primary = stabilized(decoded.primary, against: previous?.primary, label: "5h",
                                     resetCreditWasUsed: resetCreditWasUsed, pending: &pending.primary)
            let secondary = stabilized(decoded.secondary, against: previous?.secondary, label: "weekly",
                                       resetCreditWasUsed: resetCreditWasUsed, pending: &pending.secondary)
            savePendingRollbacks(pending)
            let activity = official?.activity ?? loadTokenActivity()
            let snapshot = UsageSnapshot(primary: primary, secondary: secondary, plan: decoded.plan,
                                         updatedAt: decoded.updatedAt, errorMessage: nil, activity: activity,
                                         tokenStats: official?.stats ?? loadTokenStats(activity: activity),
                                         resetCreditsRemaining: official?.resetCredits)
            save(snapshot)
            return snapshot
        } catch {
            if let cached = loadCache() {
                return UsageSnapshot(primary: cached.primary, secondary: cached.secondary, plan: cached.plan,
                                     updatedAt: cached.updatedAt, errorMessage: error.localizedDescription, activity: cached.activity,
                                     tokenStats: cached.tokenStats, resetCreditsRemaining: cached.resetCreditsRemaining)
            }
            return UsageSnapshot(primary: nil, secondary: nil, plan: nil, updatedAt: Date(), errorMessage: error.localizedDescription,
                                 activity: nil, tokenStats: nil, resetCreditsRemaining: nil)
        }
    }

    func cached() -> UsageSnapshot? { loadCache() }

    private struct Auth {
        let accessToken: String
        let accountID: String
    }

    private func loadAuth() throws -> Auth {
        let url = userHome.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url) else { throw UsageServiceError.missingAuth }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String,
              let account = tokens["account_id"] as? String,
              !access.isEmpty, !account.isEmpty else { throw UsageServiceError.invalidAuth }
        return Auth(accessToken: access, accountID: account)
    }

    private func configuredSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        let envURL = userHome.appendingPathComponent(".codex/.env")
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else {
            return URLSession(configuration: configuration)
        }
        let values = Dictionary(uniqueKeysWithValues: contents.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        })
        let rawProxy = values["HTTPS_PROXY"] ?? values["HTTP_PROXY"]
        if let rawProxy, let url = URL(string: rawProxy), let host = url.host, let port = url.port {
            configuration.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port
            ]
        }
        return URLSession(configuration: configuration)
    }

    private func decodeUsage(_ data: Data) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageServiceError.invalidResponse
        }
        let rateLimit = (root["rate_limit"] as? [String: Any]) ?? root
        let candidates = rateLimit.compactMap { key, value -> UsageWindowClassifier.Candidate? in
            guard key.hasSuffix("_window"), let window = decodeWindow(value) else { return nil }
            return UsageWindowClassifier.Candidate(sourceKey: key, window: window)
        }
        let classified = UsageWindowClassifier.classify(candidates)
        guard classified.fiveHour != nil || classified.weekly != nil else { throw UsageServiceError.invalidResponse }
        return UsageSnapshot(primary: classified.fiveHour, secondary: classified.weekly,
                             plan: root["plan_type"] as? String, updatedAt: Date(), errorMessage: nil, activity: nil,
                             tokenStats: nil, resetCreditsRemaining: nil)
    }

    private struct ActivityRow: Decodable {
        let day: String
        let tokens: Int64
    }

    private struct OfficialUsageEnvelope: Decodable {
        let id: Int?
        let result: OfficialUsageResult?
    }

    private struct OfficialRateLimitsEnvelope: Decodable {
        let id: Int?
        let result: OfficialRateLimitsResult?
    }

    private struct OfficialRateLimitsResult: Decodable {
        let rateLimitResetCredits: OfficialResetCredits?
    }

    private struct OfficialResetCredits: Decodable {
        let availableCount: Int64
    }

    private struct OfficialUsageResult: Decodable {
        let summary: OfficialUsageSummary
        let dailyUsageBuckets: [OfficialDailyBucket]?
    }

    private struct OfficialUsageSummary: Decodable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
        let longestRunningTurnSec: Int64?
        let currentStreakDays: Int?
        let longestStreakDays: Int?
    }

    private struct OfficialDailyBucket: Decodable {
        let startDate: String
        let tokens: Int64
    }

    private final class ResponseBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func appendAndContainsResponse(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            storage.append(chunk)
            let lines = String(decoding: storage, as: UTF8.self).split(separator: "\n")
            return lines.contains { $0.contains("\"id\":2") }
                && lines.contains { $0.contains("\"id\":3") }
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func loadOfficialTokenUsage() -> (activity: [TokenActivityDay], stats: TokenStats, resetCredits: Int64?)? {
        if let cached = officialUsageCache, Date().timeIntervalSince(cached.date) < 300 {
            return (cached.activity, cached.stats, cached.resetCredits)
        }
        let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let completed = DispatchSemaphore(value: 0)
        let response = ResponseBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if response.appendAndContainsResponse(chunk) { completed.signal() }
        }

        do {
            try process.run()
            let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage","version":"1.0"}}}"#
            let usageRequest = #"{"id":2,"method":"account/usage/read","params":null}"#
            let limitsRequest = #"{"id":3,"method":"account/rateLimits/read","params":null}"#
            try input.fileHandleForWriting.write(contentsOf: Data("\(initialize)\n\(usageRequest)\n\(limitsRequest)\n".utf8))
            guard completed.wait(timeout: .now() + 15) == .success else {
                process.terminate(); output.fileHandleForReading.readabilityHandler = nil; return nil
            }
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            let data = response.data
            let decoder = JSONDecoder()
            let lines = data.split(separator: 0x0A)
            guard let envelope = lines.compactMap({ try? decoder.decode(OfficialUsageEnvelope.self, from: Data($0)) })
                .first(where: { $0.id == 2 }), let result = envelope.result else { return nil }

            var values = Dictionary(uniqueKeysWithValues: (result.dailyUsageBuckets ?? []).map { ($0.startDate, $0.tokens) })
            let calendar = Calendar.current
            let todayKey = TokenActivityDay.keyFormatter.string(from: Date())
            // Official daily buckets can lag until the day is finalized. Keep
            // completed days authoritative, but fill a missing current day
            // from Codex's local state so the heatmap remains live.
            if values[todayKey] == nil, let localToday = loadTodayTokenUsage() {
                values[todayKey] = localToday
            }
            let activity = (0..<364).reversed().map { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
                let key = TokenActivityDay.keyFormatter.string(from: date)
                return TokenActivityDay(day: key, tokens: values[key] ?? 0)
            }
            let summary = result.summary
            let stats = TokenStats(cumulativeTokens: summary.lifetimeTokens ?? 0,
                                   peakDailyTokens: summary.peakDailyTokens ?? 0,
                                   longestTaskSeconds: summary.longestRunningTurnSec ?? 0,
                                   currentStreak: summary.currentStreakDays ?? 0,
                                   longestStreak: summary.longestStreakDays ?? 0)
            let resetCredits = lines.compactMap { try? decoder.decode(OfficialRateLimitsEnvelope.self, from: Data($0)) }
                .first(where: { $0.id == 3 })?.result?.rateLimitResetCredits?.availableCount
            officialUsageCache = (Date(), activity, stats, resetCredits)
            return (activity, stats, resetCredits)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            return nil
        }
    }

    private func loadTokenActivity() -> [TokenActivityDay] {
        let database = userHome.appendingPathComponent(".codex/state_5.sqlite").path
        let sql = """
        SELECT date(COALESCE(created_at_ms,created_at*1000)/1000,'unixepoch','localtime') AS day,
               SUM(tokens_used) AS tokens
        FROM threads
        WHERE COALESCE(created_at_ms,created_at*1000) >= (strftime('%s','now','-363 days','start of day')*1000)
        GROUP BY day ORDER BY day;
        """
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", database, sql]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let rows = try JSONDecoder().decode([ActivityRow].self, from: pipe.fileHandleForReading.readDataToEndOfFile())
            let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0.tokens) })
            let calendar = Calendar.current
            return (0..<364).reversed().map { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
                let key = TokenActivityDay.keyFormatter.string(from: date)
                return TokenActivityDay(day: key, tokens: values[key] ?? 0)
            }
        } catch {
            return []
        }
    }

    private func loadTodayTokenUsage() -> Int64? {
        let database = userHome.appendingPathComponent(".codex/state_5.sqlite").path
        let sql = """
        SELECT COALESCE(SUM(tokens_used),0) AS tokens
        FROM threads
        WHERE date(COALESCE(created_at_ms,created_at*1000)/1000,'unixepoch','localtime') = date('now','localtime');
        """
        struct TodayRow: Decodable { let tokens: Int64 }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", database, sql]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return try JSONDecoder().decode([TodayRow].self, from: pipe.fileHandleForReading.readDataToEndOfFile()).first?.tokens
        } catch {
            return nil
        }
    }

    private struct StatsRow: Decodable {
        let cumulative: Int64
        let longest_seconds: Int64
    }

    private func loadTokenStats(activity: [TokenActivityDay]) -> TokenStats? {
        let database = userHome.appendingPathComponent(".codex/state_5.sqlite").path
        let sql = """
        SELECT COALESCE(SUM(tokens_used),0) AS cumulative,
               COALESCE(MAX((COALESCE(updated_at_ms,updated_at*1000)-COALESCE(created_at_ms,created_at*1000))/1000),0) AS longest_seconds
        FROM threads;
        """
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", database, sql]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let row = try JSONDecoder().decode([StatsRow].self, from: pipe.fileHandleForReading.readDataToEndOfFile()).first else { return nil }
            let activeKeys = Set(activity.filter { $0.tokens > 0 }.map(\.day))
            let calendar = Calendar.current
            var current = 0
            var cursor = Date()
            while activeKeys.contains(TokenActivityDay.keyFormatter.string(from: cursor)) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            }
            var longest = 0
            var running = 0
            for item in activity {
                if item.tokens > 0 { running += 1; longest = max(longest, running) }
                else { running = 0 }
            }
            return TokenStats(cumulativeTokens: row.cumulative,
                              peakDailyTokens: activity.map(\.tokens).max() ?? 0,
                              longestTaskSeconds: row.longest_seconds,
                              currentStreak: current, longestStreak: longest)
        } catch { return nil }
    }

    private func decodeWindow(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any] else { return nil }
        let used = (object["used_percent"] as? NSNumber)?.doubleValue ?? 0
        let seconds: Int? = {
            if let number = object["limit_window_seconds"] as? NSNumber { return number.intValue }
            if let string = object["limit_window_seconds"] as? String { return Int(string) }
            return nil
        }()
        let rawReset = (object["reset_at"] as? NSNumber)?.doubleValue
        let reset = rawReset.map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
        return UsageWindow(usedPercent: used, resetAt: reset, windowSeconds: seconds)
    }

    /// Rejects one-off stale replicas while still allowing a real manual or
    /// server-side reset. A rollback is accepted immediately when the reset
    /// window advances or a reset credit is consumed, otherwise after two
    /// matching observations persisted across app/agent processes.
    private func stabilized(_ incoming: UsageWindow?, against previous: UsageWindow?, label: String,
                            resetCreditWasUsed: Bool, pending: inout PendingRollback?) -> UsageWindow? {
        guard let incoming, let previous else { pending = nil; return incoming }
        guard incoming.windowSeconds == previous.windowSeconds else { pending = nil; return incoming }

        let rolledBack = incoming.usedPercent + 0.01 < previous.usedPercent
        guard rolledBack else { pending = nil; return incoming }

        let scheduledResetOccurred: Bool = {
            guard let previousReset = previous.resetAt, let incomingReset = incoming.resetAt else { return false }
            return previousReset <= Date().addingTimeInterval(2 * 60)
                && incomingReset.timeIntervalSince(previousReset) > 60
        }()
        if scheduledResetOccurred || resetCreditWasUsed {
            pending = nil
            NSLog("Accepted confirmed %@ quota reset", label)
            return incoming
        }

        let now = Date()
        if var candidate = pending,
           now.timeIntervalSince(candidate.firstSeenAt) <= 15 * 60,
           abs(candidate.usedPercent - incoming.usedPercent) <= 0.5,
           candidate.windowSeconds == incoming.windowSeconds,
           resetDatesMatch(candidate.resetAt, incoming.resetAt) {
            candidate.confirmations += 1
            if candidate.confirmations >= 3 {
                pending = nil
                NSLog("Accepted %@ quota rollback after consecutive confirmation", label)
                return incoming
            }
            pending = candidate
        } else {
            pending = PendingRollback(usedPercent: incoming.usedPercent, resetAt: incoming.resetAt,
                                      windowSeconds: incoming.windowSeconds, firstSeenAt: now, confirmations: 1)
        }

        NSLog("Held unconfirmed %@ quota rollback (%.2f%% -> %.2f%%)", label, previous.usedPercent, incoming.usedPercent)
        return previous
    }

    private func resetDatesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?): return abs(left.timeIntervalSince(right)) <= 60
        case (nil, nil): return true
        default: return false
        }
    }

    private func loadPendingRollbacks() -> PendingRollbackState {
        guard let data = try? Data(contentsOf: pendingRollbackURL),
              let state = try? JSONDecoder().decode(PendingRollbackState.self, from: data) else {
            return PendingRollbackState(primary: nil, secondary: nil)
        }
        return state
    }

    private func savePendingRollbacks(_ state: PendingRollbackState) {
        if state.primary == nil, state.secondary == nil {
            try? FileManager.default.removeItem(at: pendingRollbackURL)
            return
        }
        try? FileManager.default.createDirectory(at: pendingRollbackURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: pendingRollbackURL, options: .atomic)
    }

    private func save(_ snapshot: UsageSnapshot) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCache() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else { return nil }
        let candidates = [
            snapshot.primary.map { UsageWindowClassifier.Candidate(sourceKey: "primary_window", window: $0) },
            snapshot.secondary.map { UsageWindowClassifier.Candidate(sourceKey: "secondary_window", window: $0) }
        ].compactMap { $0 }
        let classified = UsageWindowClassifier.classify(candidates)
        guard classified.fiveHour != snapshot.primary || classified.weekly != snapshot.secondary else {
            return snapshot
        }
        return UsageSnapshot(primary: classified.fiveHour, secondary: classified.weekly,
                             plan: snapshot.plan, updatedAt: snapshot.updatedAt,
                             errorMessage: snapshot.errorMessage, activity: snapshot.activity,
                             tokenStats: snapshot.tokenStats,
                             resetCreditsRemaining: snapshot.resetCreditsRemaining)
    }
}
