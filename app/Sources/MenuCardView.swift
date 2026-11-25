import SwiftUI

struct MenuCardView: View {
    @ObservedObject var model: StatusModel

    var onToggleCard: () -> Void
    var onToggleInterval: () -> Void
    var onRefresh: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            engineBlock(
                title: "CODEX",
                engine: .codex,
                state: model.codexState,
                updatedAt: model.codexUpdatedAt,
                errorText: model.codexError
            )

            Divider().opacity(0.4)

            engineBlock(
                title: "ANTIGRAVITY",
                engine: .antigravity,
                state: model.agyState,
                updatedAt: model.agyUpdatedAt,
                errorText: model.agyError
            )

            if !model.agyState.extras.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.agyState.extras) { extra in
                        HStack {
                            Text(extra.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let r5 = extra.fiveHourRemain {
                                Text("5h \(r5)%")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if let rw = extra.weeklyRemain {
                                Text("周 \(rw)%")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider().opacity(0.4)

            HStack(spacing: 7) {
                Button(action: onToggleCard) {
                    Text(model.cardVisible ? "隐藏卡片" : "显示卡片")
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: Palette.engineTone(.antigravity, tier: .ok).accent).opacity(0.85))

                Button(action: onToggleInterval) {
                    Text(model.intervalSeconds == 60 ? "1m" : "3m")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 28, height: 18)
                }
                .buttonStyle(.bordered)
                .help("切换自动刷新频率（1 分钟 / 3 分钟）")

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20, height: 18)
                        .opacity(model.isRefreshing ? 0.35 : 1)
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("立即刷新全部额度")

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.borderless)
                .help("退出")
            }
        }
        .padding(13)
        .frame(width: 274)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private func engineBlock(
        title: String,
        engine: Palette.Engine,
        state: QuotaState,
        updatedAt: Date?,
        errorText: String?
    ) -> some View {
        let five = state.fiveHour
        let week = state.weekly
        let remain = five.map { max(0, min(100, $0.remainingPercent)) } ?? 100
        let tier = Palette.tier(forRemaining: remain)
        let tone = Palette.engineTone(engine, tier: tier)
        let accent = Color(nsColor: tone.accent)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(title)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let five {
                    Text("\(Self.clock.string(from: five.resetsAt)) 重置 · \(countdownText(until: five.resetsAt))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if let updatedAt {
                    Text("更新于 \(Self.clock.string(from: updatedAt))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if five != nil {
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                        Text("\(Int(remain.rounded()))")
                            .font(.system(size: 24, weight: .bold))
                            .monospacedDigit()
                            .fixedSize()
                            .foregroundStyle(tier == .ok ? .primary : accent)
                        Text("%")
                            .font(.system(size: 10, weight: .semibold))
                            .fixedSize()
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 68, alignment: .leading)

                    VStack(spacing: 5) {
                        ProgressBar(remain: remain, tone: tone, height: 5)
                        if let week {
                            let wRem = max(0, min(100, week.remainingPercent))
                            let wTier = Palette.tier(forRemaining: wRem)
                            let wTone = Palette.engineTone(engine, tier: wTier)
                            HStack(spacing: 5) {
                                Text("周")
                                    .font(.system(size: 9))
                                    .fixedSize()
                                    .foregroundStyle(.tertiary)
                                Text("\(Int(wRem.rounded()))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .fixedSize()
                                    .foregroundStyle(wTier == .ok ? .secondary : Color(nsColor: wTone.accent))
                                ProgressBar(remain: wRem, tone: wTone, height: 3.5)
                                Text(Self.dateClock.string(from: week.resetsAt))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .fixedSize()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else {
                Text(errorText ?? "正在读取…")
                    .font(.system(size: 10))
                    .foregroundStyle(errorText != nil ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
    }

    private func countdownText(until date: Date) -> String {
        let mins = max(0, Int(date.timeIntervalSinceNow / 60))
        if mins == 0 { return "已重置" }
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? String(format: "剩 %dh%02dm", h, m) : "剩 \(m)m"
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()
}

private struct ProgressBar: View {
    let remain: Double
    let tone: Palette.Tone
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(nsColor: tone.fillFrom), Color(nsColor: tone.fillTo)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * CGFloat(remain / 100)))
            }
        }
        .frame(height: height)
    }
}
