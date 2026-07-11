import Foundation

struct UsageWindow: Codable, Hashable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Int?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
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
    private let userHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? "/Users/\(NSUserName())", isDirectory: true)
    private let sandboxHome = FileManager.default.homeDirectoryForCurrentUser
    private var isWidget: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".widget") == true }
    private var officialUsageCache: (date: Date, activity: [TokenActivityDay], stats: TokenStats, resetCredits: Int64?)?
    private lazy var cacheURL = (isWidget ? sandboxHome : userHome)
        .appendingPathComponent("Library/Caches/com.codexmeter.shared/usage.json")

    func fetch() async -> UsageSnapshot {
        // The host app owns credentials and networking. The widget reads the
        // mirrored snapshot from its own sandbox container.
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
            let official = loadOfficialTokenUsage()
            let activity = official?.activity ?? loadTokenActivity()
            let snapshot = UsageSnapshot(primary: decoded.primary, secondary: decoded.secondary, plan: decoded.plan,
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
        let primary = decodeWindow(rateLimit["primary_window"])
        let secondary = decodeWindow(rateLimit["secondary_window"])
        guard primary != nil || secondary != nil else { throw UsageServiceError.invalidResponse }
        return UsageSnapshot(primary: primary, secondary: secondary,
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
        let seconds = (object["limit_window_seconds"] as? NSNumber)?.intValue
        let rawReset = (object["reset_at"] as? NSNumber)?.doubleValue
        let reset = rawReset.map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
        return UsageWindow(usedPercent: used, resetAt: reset, windowSeconds: seconds)
    }

    private func save(_ snapshot: UsageSnapshot) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        if !isWidget {
            let widgetCache = userHome
                .appendingPathComponent("Library/Containers/com.eko.CodexMeter.widget/Data/Library/Caches/com.codexmeter.shared/usage.json")
            try? FileManager.default.createDirectory(at: widgetCache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: widgetCache, options: .atomic)
        }
    }

    private func loadCache() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
