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
        } else {
            standardView
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
            if family == .systemMedium {
                Spacer(minLength: 0)
                UsageBar(title: "5 小时", window: entry.snapshot.primary, accent: usageColor(for: entry.snapshot.primary), compact: true)
                UsageBar(title: "每周", window: entry.snapshot.secondary, accent: usageColor(for: entry.snapshot.secondary), compact: true)
                Spacer(minLength: 0)
            } else {
                TokenActivityChart(days: entry.snapshot.activity ?? [], fixedGridHeight: 54, stats: entry.snapshot.tokenStats)
                UsageBar(title: "5 小时额度", window: entry.snapshot.primary, accent: usageColor(for: entry.snapshot.primary))
                Divider().opacity(0.45)
                UsageBar(title: "每周额度", window: entry.snapshot.secondary, accent: usageColor(for: entry.snapshot.secondary))
            }
        }
    }

    private var smallView: some View {
        VStack(spacing: 5) {
            HStack {
                Text("CodexMeter")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                Spacer()
                if entry.snapshot.errorMessage != nil {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ConcentricUsageRings(primary: entry.snapshot.primary, secondary: entry.snapshot.secondary)
            Text("周剩余 \(Int((entry.snapshot.secondary?.remainingPercent ?? 0).rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
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
