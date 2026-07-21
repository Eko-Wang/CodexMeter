import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), snapshot: .previewSample) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(UsageEntry(date: Date(), snapshot: await UsageService.shared.cached() ?? .empty)) }
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
            if let fiveHour = entry.snapshot.primary {
                UsageBar(title: "5 小时", window: fiveHour, accent: usageColor(for: fiveHour), compact: true)
            }
            if let weekly = entry.snapshot.secondary {
                UsageBar(title: "每周", window: weekly, accent: weeklyUsageColor(for: weekly), compact: true)
            }
            if entry.snapshot.primary == nil, entry.snapshot.secondary == nil {
                Text("额度数据等待同步")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        GeometryReader { proxy in
            ZStack {
                if entry.snapshot.primary != nil, entry.snapshot.secondary != nil {
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: proxy.size.height - 14))
                        path.addLine(to: CGPoint(x: proxy.size.width - 10, y: 14))
                    }
                    .stroke(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }

                if entry.snapshot.primary != nil, entry.snapshot.secondary != nil {
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
                } else if let fiveHour = entry.snapshot.primary {
                    singleQuotaView(prefix: "H", window: fiveHour, color: usageColor(for: fiveHour))
                } else if let weekly = entry.snapshot.secondary {
                    singleQuotaView(prefix: "W", window: weekly, color: weeklyUsageColor(for: weekly))
                } else {
                    Text("—")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quotaAccessibilityLabel)
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
                TokenActivityChart(days: activity, fixedGridHeight: 50,
                                   stats: entry.snapshot.tokenStats,
                                   showsDetails: hasSingleQuota)
            } else {
                HStack {
                    Label("Token 活动等待同步", systemImage: "square.grid.3x3.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 50)
            }
            if let fiveHour = entry.snapshot.primary {
                UsageBar(title: "5 小时额度", window: fiveHour,
                         accent: usageColor(for: fiveHour), compact: true)
            }
            if entry.snapshot.primary != nil, entry.snapshot.secondary != nil {
                Divider().opacity(0.35)
            }
            if let weekly = entry.snapshot.secondary {
                UsageBar(title: "每周额度", window: weekly,
                         accent: weeklyUsageColor(for: weekly), compact: true)
            }
            if entry.snapshot.primary == nil, entry.snapshot.secondary == nil {
                Text("额度数据等待同步")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quotaLabel(prefix: String, window: UsageWindow?, color: Color,
                            numberSize: CGFloat = 38, markerSize: CGFloat = 12) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(prefix)·")
                .font(.system(size: markerSize, weight: .bold, design: .rounded))
            Text(window.map { "\(remaining($0))" } ?? "—")
                .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
            if window != nil {
                Text("%")
                    .font(.system(size: markerSize, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func singleQuotaView(prefix: String, window: UsageWindow, color: Color) -> some View {
        VStack(spacing: 6) {
            quotaLabel(prefix: prefix, window: window, color: color,
                       numberSize: 48, markerSize: 13)
            Text(usageResetText(for: window))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var hasSingleQuota: Bool {
        (entry.snapshot.primary == nil) != (entry.snapshot.secondary == nil)
    }

    private func remaining(_ window: UsageWindow?) -> Int {
        Int((window?.remainingPercent ?? 0).rounded())
    }

    private var quotaAccessibilityLabel: String {
        var parts: [String] = []
        if let fiveHour = entry.snapshot.primary {
            parts.append("5 小时剩余 \(remaining(fiveHour))%")
        }
        if let weekly = entry.snapshot.secondary {
            parts.append("每周剩余 \(remaining(weekly))%")
        }
        return parts.isEmpty ? "额度数据等待同步" : parts.joined(separator: "，")
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
    // Keep the original stable kind so existing desktop placements and new
    // gallery additions use the same descriptor.
    let kind = "CodexMeterWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            CodexWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexMeter")
        .description("自动识别并查看 Codex 当前额度剩余情况。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
