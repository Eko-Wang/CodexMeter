import SwiftUI

enum CodexTheme {
    static let ink = Color(red: 0.13, green: 0.12, blue: 0.10)
    static let cream = Color(red: 0.98, green: 0.94, blue: 0.83)
    static let card = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let nightPaper = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let nightCard = Color(red: 0.17, green: 0.16, blue: 0.14)
    static let yellow = Color(red: 1.00, green: 0.84, blue: 0.35)
    static let coral = Color(red: 0.94, green: 0.35, blue: 0.20)
    static let sky = Color(red: 0.57, green: 0.78, blue: 0.94)
    static let pink = Color(red: 0.94, green: 0.68, blue: 0.76)
    static let mint = Color(red: 0.67, green: 0.85, blue: 0.70)

    static func paper(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nightPaper : cream
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nightCard : card
    }

    static func line(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.82) : ink
    }

    static func muted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : ink.opacity(0.58)
    }
}

struct PaperDotGrid: View {
    @Environment(\.colorScheme) private var colorScheme
    var spacing: CGFloat = 18
    var dotSize: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            let color = CodexTheme.line(for: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.075)
            for x in stride(from: spacing / 2, through: size.width, by: spacing) {
                for y in stride(from: spacing / 2, through: size.height, by: spacing) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(color)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PaperCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let shadowOffset: CGFloat
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(CodexTheme.line(for: colorScheme).opacity(colorScheme == .dark ? 0.34 : 0.92))
                        .offset(x: shadowOffset, y: shadowOffset)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(CodexTheme.card(for: colorScheme))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CodexTheme.line(for: colorScheme), lineWidth: lineWidth)
            }
    }
}

extension View {
    func paperCard(cornerRadius: CGFloat = 18, shadowOffset: CGFloat = 6, lineWidth: CGFloat = 2) -> some View {
        modifier(PaperCardModifier(cornerRadius: cornerRadius, shadowOffset: shadowOffset, lineWidth: lineWidth))
    }
}

struct UsageBar: View {
    let title: String
    let window: UsageWindow?
    let accent: Color
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .heavy))
                Spacer()
                Text(window.map { "剩余 \(Int($0.remainingPercent.rounded()))%" } ?? "—")
                    .font(.system(compact ? .caption : .subheadline, design: .monospaced, weight: .bold))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(CodexTheme.line(for: colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.10))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent)
                        .frame(width: max(0, proxy.size.width * CGFloat((window?.remainingPercent ?? 0) / 100)))
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(CodexTheme.line(for: colorScheme).opacity(0.18), lineWidth: 1))
            }
            .frame(height: compact ? 8 : 11)
            if !compact {
                HStack {
                    Text("WINDOW / RESET")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                    Spacer()
                    Text(usageResetText(for: window))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text(usageResetText(for: window))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(window.map { "剩余 \(Int($0.remainingPercent.rounded()))%，\(usageResetText(for: $0))" } ?? "暂无数据")
    }
}

func usageResetText(for window: UsageWindow?) -> String {
    guard let date = window?.resetAt else { return "重置时间未知" }
    let seconds = max(0, date.timeIntervalSinceNow)
    let countdown: String
    if seconds < 3600 { countdown = "\(max(1, Int(seconds / 60))) 分钟" }
    else if seconds < 86_400 { countdown = "\(Int(seconds / 3600)) 小时 \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)) 分" }
    else { countdown = "\(Int(seconds / 86_400)) 天 \(Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600)) 小时" }
    let absolute = date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    return "\(countdown) · \(absolute)"
}

func usageColor(for window: UsageWindow?) -> Color {
    let t = max(0, min(1, (window?.remainingPercent ?? 0) / 100))
    let red = 0.94 + (0.18 - 0.94) * t
    let green = 0.22 + (0.82 - 0.22) * t
    let blue = 0.24 + (0.36 - 0.24) * t
    return Color(red: red, green: green, blue: blue)
}

func weeklyUsageColor(for window: UsageWindow?) -> Color {
    let t = max(0, min(1, (window?.remainingPercent ?? 0) / 100))
    // A direct red-to-blue scale keeps urgency readable without introducing
    // the yellow midpoint used by conventional traffic-light palettes.
    let red = 0.94 + (0.12 - 0.94) * t
    let green = 0.22 + (0.55 - 0.22) * t
    let blue = 0.24 + (0.96 - 0.24) * t
    return Color(red: red, green: green, blue: blue)
}

struct TokenActivityChart: View {
    let days: [TokenActivityDay]
    var compact = false
    var fixedGridHeight: CGFloat? = nil
    var stats: TokenStats? = nil
    var showsDetails = false
    @State private var hoveredDay: TokenActivityDay?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Token 活动")
                    .font(.system(compact ? .caption2 : .subheadline, design: .rounded, weight: .heavy))
                Spacer()
                Text(summaryText)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                let gap: CGFloat = compact ? 1 : 1.4
                let widthCell = (proxy.size.width - gap * 51) / 52
                let cell = max(2, widthCell)
                let xOffset: CGFloat = 0
                Canvas { context, size in
                    let recent = Array(days.suffix(364))
                    let maxValue = max(1, recent.map(\.tokens).max() ?? 1)
                    for (index, item) in recent.enumerated() {
                        let column = index / 7
                        let row = index % 7
                        let rect = CGRect(x: xOffset + CGFloat(column) * (cell + gap),
                                          y: CGFloat(row) * (cell + gap),
                                          width: cell, height: cell)
                        let intensity = sqrt(Double(item.tokens) / Double(maxValue))
                        let color: Color
                        if item.tokens == 0 { color = CodexTheme.line(for: colorScheme).opacity(colorScheme == .dark ? 0.11 : 0.075) }
                        else if intensity <= 0.20 { color = Color(red: 0.76, green: 0.88, blue: 1.00) }
                        else if intensity <= 0.40 { color = Color(red: 0.49, green: 0.75, blue: 1.00) }
                        else if intensity <= 0.60 { color = Color(red: 0.25, green: 0.61, blue: 0.96) }
                        else if intensity <= 0.80 { color = Color(red: 0.08, green: 0.44, blue: 0.86) }
                        else { color = Color(red: 0.02, green: 0.27, blue: 0.66) }
                        let path = Path(roundedRect: rect, cornerRadius: min(1.8, cell * 0.28))
                        context.fill(path, with: .color(color))
                        if item.tokens > 0 {
                            context.stroke(path, with: .color(CodexTheme.line(for: colorScheme).opacity(0.48)), lineWidth: max(0.45, cell * 0.07))
                        }
                    }
                }
                .onContinuousHover { phase in
                    guard showsDetails else { return }
                    switch phase {
                    case .active(let point):
                        let column = Int((point.x - xOffset) / (cell + gap))
                        let row = Int(point.y / (cell + gap))
                        let index = column * 7 + row
                        let recent = Array(days.suffix(364))
                        hoveredDay = recent.indices.contains(index) ? recent[index] : nil
                    case .ended:
                        hoveredDay = nil
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hoveredDay, showsDetails {
                        Text("\(displayDate(hoveredDay.day))  ·  \(format(hoveredDay.tokens)) tokens")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .foregroundStyle(CodexTheme.ink)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7).fill(CodexTheme.ink.opacity(0.8)).offset(x: 2, y: 2)
                                    RoundedRectangle(cornerRadius: 7).fill(CodexTheme.yellow)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CodexTheme.ink, lineWidth: 1.4))
                            .allowsHitTesting(false)
                    }
                }
            }
            .aspectRatio(52.0 / 7.0, contentMode: .fit)
            .frame(height: fixedGridHeight)
            if !compact {
                HStack {
                    ForEach(monthLabels, id: \.self) { month in
                        Text(month).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            }
            if showsDetails, let stats {
                HStack(spacing: 0) {
                    metric(format(stats.cumulativeTokens), "累计 Token 数", tint: CodexTheme.yellow)
                    metric(format(stats.peakDailyTokens), "峰值 Token 数", tint: CodexTheme.pink)
                    metric(duration(stats.longestTaskSeconds), "最长任务时长", tint: CodexTheme.sky)
                    metric("\(stats.currentStreak) 天", "当前连续天数", tint: CodexTheme.mint)
                    metric("\(stats.longestStreak) 天", "最长连续天数", tint: CodexTheme.coral.opacity(0.72))
                }
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(CodexTheme.line(for: colorScheme), lineWidth: 1.3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token 活动")
        .accessibilityValue(summaryText)
    }

    private var summaryText: String {
        let today = days.last?.tokens ?? 0
        let monthKey = String(TokenActivityDay.keyFormatter.string(from: Date()).prefix(7))
        let month = days.filter { $0.day.hasPrefix(monthKey) }.reduce(Int64(0)) { $0 + $1.tokens }
        return "今日 \(format(today))  ·  本月 \(format(month))  ·  累计 \(format(stats?.cumulativeTokens ?? days.reduce(0) { $0 + $1.tokens }))"
    }

    private func metric(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(tint.opacity(colorScheme == .dark ? 0.55 : 0.78))
        .overlay(alignment: .trailing) {
            Rectangle().fill(CodexTheme.line(for: colorScheme).opacity(0.28)).frame(width: 1)
        }
    }

    private func format(_ value: Int64) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
    private func duration(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分钟"
    }
    private func displayDate(_ key: String) -> String {
        guard let date = TokenActivityDay.keyFormatter.date(from: key) else { return key }
        return date.formatted(.dateTime.year().month().day())
    }
    private var monthLabels: [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        let end = Date()
        return (-11...0).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: end).map { formatter.string(from: $0) }
        }
    }
}


struct BrandMark: View {
    // One canonical 7×7 mark: the top stroke sits on row 2 and
    // the left stroke sits on column 2, matching the application icon.
    private let active: Set<Int> = [8,9,10,11, 15,22,29, 36,37,38,39]

    var body: some View {
        VStack(spacing: 1.25) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 1.25) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        RoundedRectangle(cornerRadius: 1)
                            .fill(active.contains(index)
                                  ? Color(red: 0.39, green: 0.70, blue: 1.0)
                                  : Color.white.opacity(0.13))
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .padding(4.6)
        .frame(width: 34, height: 34)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodexTheme.ink.opacity(0.82))
                    .offset(x: 2.5, y: 2.5)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodexTheme.ink)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18)))
    }
}
