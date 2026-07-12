import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(UsageEntry(date: Date(), snapshot: await UsageService.shared.cached() ?? .placeholder)) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let snapshot = await UsageService.shared.fetch()
            let entry = UsageEntry(date: Date(), snapshot: snapshot)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
        }
    }
}

struct CodexWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if family == .systemSmall {
            smallView
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "codexusage://dashboard"))
        } else if family == .systemMedium {
            standardView
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "codexusage://dashboard"))
        } else {
            largeView
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "codexusage://dashboard"))
        }
    }

    private var standardView: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 9 : 13) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CodexMeter").font(.system(.headline, design: .rounded, weight: .bold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let count = entry.snapshot.resetCreditsRemaining {
                    Text("可重置 \(count) 次")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if entry.snapshot.errorMessage != nil {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            UsageBar(title: "5 小时", window: entry.snapshot.primary, accent: usageColor(for: entry.snapshot.primary), compact: true)
            UsageBar(title: "每周", window: entry.snapshot.secondary, accent: weeklyUsageColor(for: entry.snapshot.secondary), compact: true)
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: proxy.size.height - 14))
                    path.addLine(to: CGPoint(x: proxy.size.width - 10, y: 14))
                }
                .stroke(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round))

                VStack(spacing: 0) {
                    HStack {
                        quotaLabel(prefix: "H", window: entry.snapshot.primary,
                                   color: usageColor(for: entry.snapshot.primary))
                        Spacer(minLength: 24)
                    }
                    Spacer(minLength: 18)
                    HStack {
                        Spacer(minLength: 24)
                        quotaLabel(prefix: "W", window: entry.snapshot.secondary,
                                   color: weeklyUsageColor(for: entry.snapshot.secondary))
                    }
                }
                .padding(3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5 小时剩余 \(remaining(entry.snapshot.primary))%，每周剩余 \(remaining(entry.snapshot.secondary))%")
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CodexMeter").font(.system(.headline, design: .rounded, weight: .bold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let count = entry.snapshot.resetCreditsRemaining {
                    Text("可重置 \(count) 次").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            if let activity = entry.snapshot.activity, !activity.isEmpty {
                TokenActivityChart(days: activity, fixedGridHeight: 50, stats: entry.snapshot.tokenStats)
            } else {
                HStack {
                    Label("Token 活动等待同步", systemImage: "square.grid.3x3.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 50)
            }
            UsageBar(title: "5 小时额度", window: entry.snapshot.primary,
                     accent: usageColor(for: entry.snapshot.primary), compact: true)
            Divider().opacity(0.35)
            UsageBar(title: "每周额度", window: entry.snapshot.secondary,
                     accent: weeklyUsageColor(for: entry.snapshot.secondary), compact: true)
        }
    }

    private func quotaLabel(prefix: String, window: UsageWindow?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(prefix)·")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(window.map { "\(remaining($0))" } ?? "—")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
            if window != nil {
                Text("%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func remaining(_ window: UsageWindow?) -> Int {
        Int((window?.remainingPercent ?? 0).rounded())
    }

    private var subtitle: String {
        if entry.snapshot.errorMessage != nil { return "显示缓存 · 打开 App 检查" }
        return "更新于 \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

@main
struct CodexMeterWidgetBundle: WidgetBundle {
    var body: some Widget { CodexMeterWidget() }
}

struct CodexMeterWidget: Widget {
    // V2 separates the current descriptor from the stale pre-CodexMeter
    // descriptor cached by macOS under the original kind.
    let kind = "CodexMeterWidgetV2"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            CodexWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexMeter")
        .description("查看 5 小时与每周额度剩余情况。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
