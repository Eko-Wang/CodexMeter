import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct CodexMeterApp: App {
    init() {
        LoginItemManager.enableIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["dashboard"])
    }
}

enum LoginItemManager {
    static func enableIfNeeded() {
        enable(SMAppService.mainApp, label: "main")
        enableAgent()
    }

    private static func enableAgent() {
        // Public builds 17, 20 and 27 used these labels. Keep only this
        // published upgrade chain so older installations do not leave a
        // second background refresher running after an update.
        let publishedLegacyPlists = [
            "com.eko.CodexMeter.agent.plist",
            "com.eko.CodexMeter.agent.v2.plist",
            "com.eko.CodexMeter.agent.v3.plist",
            "com.eko.CodexMeter.agent.v4.plist",
            "com.eko.CodexMeter.agent.v5.plist",
            "com.eko.CodexMeter.agent.v6.plist",
            "com.eko.CodexMeter.agent.v7.plist"
        ]
        for plistName in publishedLegacyPlists {
            let legacyService = SMAppService.agent(plistName: plistName)
            if legacyService.status != .notRegistered {
                try? legacyService.unregister()
            }
        }
        let service = SMAppService.agent(plistName: "com.eko.CodexMeter.agent.v10.plist")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let registeredBuild = UserDefaults.standard.string(forKey: "registeredAgentBuild")
        if service.status == .enabled, registeredBuild != build {
            do {
                try service.unregister()
                record("updating", label: "agent")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    enable(service, label: "agent")
                    if service.status == .enabled {
                        UserDefaults.standard.set(build, forKey: "registeredAgentBuild")
                    }
                }
                return
            } catch {
                NSLog("Unable to replace background agent: %@", error.localizedDescription)
            }
        }
        enable(service, label: "agent")
        if service.status == .enabled {
            UserDefaults.standard.set(build, forKey: "registeredAgentBuild")
        }
    }

    private static func enable(_ service: SMAppService, label: String) {
        guard service.status != .enabled else {
            record("enabled", label: label)
            return
        }
        do {
            try service.register()
            record(statusName(service.status), label: label)
        } catch {
            NSLog("Unable to enable %@ service: %@", label, error.localizedDescription)
            record("error: \(error.localizedDescription)", label: label)
        }
    }

    private static func statusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    private static func record(_ status: String, label: String) {
        UserDefaults.standard.set(status, forKey: "\(label)ServiceStatus")
    }
}

struct DashboardView: View {
    @State private var snapshot = UsageSnapshot.empty
    @State private var loading = true
    @State private var hasLoaded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CodexMeter")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                        Text(statusText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let count = snapshot.resetCreditsRemaining {
                        Label("可重置 \(count) 次", systemImage: "arrow.counterclockwise.circle")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(CodexTheme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background {
                                ZStack {
                                    Capsule().fill(CodexTheme.ink.opacity(0.82)).offset(x: 2.5, y: 2.5)
                                    Capsule().fill(CodexTheme.yellow)
                                }
                            }
                            .overlay(Capsule().stroke(CodexTheme.ink, lineWidth: 1.6))
                    }
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CodexTheme.ink)
                            .frame(width: 36, height: 30)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(CodexTheme.ink.opacity(0.82))
                                        .offset(x: 2.5, y: 2.5)
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(CodexTheme.sky)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CodexTheme.ink, lineWidth: 1.6))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                    .opacity(loading ? 0.55 : 1)
                    .help("立即刷新")
                    .accessibilityLabel("立即刷新 CodexMeter 用量")
                }

                VStack(spacing: 18) {
                    if let activity = snapshot.activity, !activity.isEmpty {
                        TokenActivityChart(days: activity, stats: snapshot.tokenStats, showsDetails: true)
                    } else {
                        ActivityLoadingView(isLoading: loading && !hasLoaded)
                    }
                    if loading && !hasLoaded {
                        Rectangle()
                            .fill(CodexTheme.line(for: colorScheme).opacity(0.22))
                            .frame(height: 1)
                        QuotaLoadingView()
                    } else {
                        if snapshot.primary != nil || snapshot.secondary != nil {
                            Rectangle()
                                .fill(CodexTheme.line(for: colorScheme).opacity(0.22))
                                .frame(height: 1)
                        }
                        if let fiveHour = snapshot.primary {
                            UsageBar(title: "5 小时", window: fiveHour, accent: usageColor(for: fiveHour))
                        }
                        if snapshot.primary != nil, snapshot.secondary != nil {
                            Rectangle()
                                .fill(CodexTheme.line(for: colorScheme).opacity(0.22))
                                .frame(height: 1)
                        }
                        if let weekly = snapshot.secondary {
                            UsageBar(title: "每周", window: weekly, accent: weeklyUsageColor(for: weekly))
                        }
                        if snapshot.primary == nil, snapshot.secondary == nil {
                            Text(snapshot.errorMessage == nil ? "当前没有可用的额度窗口" : "额度数据暂时不可用")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                    }
                }
                .padding(22)
                .paperCard(cornerRadius: 18, shadowOffset: 7, lineWidth: 2.2)

                if let error = snapshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CodexTheme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(CodexTheme.pink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(CodexTheme.ink, lineWidth: 1.3))
                }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(minWidth: 560, idealWidth: 760)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                CodexTheme.paper(for: colorScheme)
                PaperDotGrid(spacing: 22, dotSize: 1.7)
            }
            .ignoresSafeArea()
        }
        .task { await refresh() }
        .onOpenURL { _ in
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var statusText: String {
        if loading { return "正在同步…" }
        if snapshot.errorMessage != nil {
            return "缓存于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }
    private func refresh() async {
        loading = true
        if !hasLoaded, let cached = await UsageService.shared.cached() {
            snapshot = cached.historyOnly
        }
        let refreshed = await UsageService.shared.fetch()
        snapshot = refreshed
        hasLoaded = true
        loading = false
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexMeterWidget")
    }
}

private struct ActivityLoadingView: View {
    let isLoading: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token 活动")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("暂无活动数据")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                let gap: CGFloat = 1.4
                let cell = max(2, (proxy.size.width - gap * 51) / 52)
                Canvas { context, _ in
                    let color = CodexTheme.line(for: colorScheme)
                        .opacity(colorScheme == .dark ? 0.11 : 0.075)
                    for column in 0..<52 {
                        for row in 0..<7 {
                            let rect = CGRect(x: CGFloat(column) * (cell + gap),
                                              y: CGFloat(row) * (cell + gap),
                                              width: cell, height: cell)
                            context.fill(Path(roundedRect: rect, cornerRadius: min(1.8, cell * 0.28)),
                                         with: .color(color))
                        }
                    }
                }
            }
            .aspectRatio(52.0 / 7.0, contentMode: .fit)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0)
                        .fill(CodexTheme.line(for: colorScheme).opacity(index.isMultiple(of: 2) ? 0.08 : 0.05))
                }
            }
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CodexTheme.line(for: colorScheme).opacity(0.18), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "正在同步 Token 活动" : "暂无 Token 活动数据")
    }
}

private struct QuotaLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("正在确认额度窗口")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                Spacer()
                Text("—")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(CodexTheme.line(for: colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.10))
                .frame(height: 11)
            Text("实时数据返回前不显示缓存额度")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在确认当前额度窗口")
    }
}
