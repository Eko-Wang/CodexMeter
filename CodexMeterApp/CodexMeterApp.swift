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
    @State private var snapshot = UsageSnapshot.placeholder
    @State private var loading = true
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
                    TokenActivityChart(days: snapshot.activity ?? [], stats: snapshot.tokenStats, showsDetails: true)
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
        return "更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }
    private func refresh() async {
        loading = true
        snapshot = await UsageService.shared.fetch()
        loading = false
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexMeterWidget")
    }
}
