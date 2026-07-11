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
                .frame(minWidth: 520, minHeight: 430)
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["dashboard"])
    }
}

enum LoginItemManager {
    static func enableIfNeeded() {
        enable(SMAppService.mainApp, label: "main")
        enable(SMAppService.agent(plistName: "com.eko.CodexMeter.agent.plist"), label: "agent")
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

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            LinearGradient(colors: [Color(red: 0.10, green: 0.47, blue: 0.91).opacity(0.10), .clear, Color(red: 0.39, green: 0.70, blue: 1).opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CodexMeter")
                            .font(.custom("Avenir Next", size: 23).weight(.semibold))
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let count = snapshot.resetCreditsRemaining {
                        Label("可重置 \(count) 次", systemImage: "arrow.counterclockwise.circle")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.primary.opacity(0.055), in: Capsule())
                    }
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(loading)
                    .help("立即刷新")
                    .accessibilityLabel("立即刷新 CodexMeter 用量")
                }

                VStack(spacing: 20) {
                    TokenActivityChart(days: snapshot.activity ?? [], stats: snapshot.tokenStats, showsDetails: true)
                    Divider().opacity(0.5)
                    UsageBar(title: "5 小时", window: snapshot.primary, accent: usageColor(for: snapshot.primary))
                    Divider().opacity(0.5)
                    UsageBar(title: "每周", window: snapshot.secondary, accent: weeklyUsageColor(for: snapshot.secondary))
                }
                .padding(22)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.16)))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

                if let error = snapshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}
