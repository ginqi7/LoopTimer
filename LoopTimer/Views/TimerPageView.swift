//
//  TimerPageView.swift
//  LoopTimer
//
//  Page 1 — "计时". Input lives here, and it is the only page that starts or
//  stops a session.
//
//  Input is deliberately two fields: a name, and a duration in minutes.
//  A duration of 0 means "no duration" → stopwatch mode (mode 2).
//

import SwiftUI

struct TimerPageView: View {
    @ObservedObject var store: SessionStore

    @State private var draftTitle: String = ""
    /// Typed duration in minutes. "0" (or empty) means: no duration → 不定时.
    @AppStorage("inputMinutes") private var minutesText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case duration
    }

    /// Parsed duration, in seconds. 0 → 不定时.
    private var plannedSeconds: TimeInterval {
        let minutes = Int(minutesText.filter(\.isNumber).prefix(4)) ?? 0
        return TimeInterval(max(0, minutes) * 60)
    }

    private var isTimed: Bool { plannedSeconds > 0 }

    private var canStart: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let active = store.active {
                // While a session runs, the card owns the page.
                Spacer(minLength: 0)
                runningCard(active)
                Spacer(minLength: 0)
            } else {
                // Idle: recent records on top, input anchored at the bottom, so the
                // page never looks like an empty form floating in space.
                recentSection
                    .padding(.top, 12)
                Spacer(minLength: 16)
                inputCard
            }

            footer
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
    }

    // MARK: - Running

    private func runningCard(_ session: Session) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(session.startedAt.timeText() + " 开始")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(displayedClock(for: session))
                .font(.system(size: 72, weight: .thin, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(caption(for: session))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let planned = session.plannedDuration, planned > 0 {
                ProgressView(value: min(1, store.activeElapsed / planned))
                    .tint(.accentColor)
            }

            Button {
                store.stopActive()
            } label: {
                Label("停止并记录", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.red.opacity(0.12))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if store.liveActivityState.isProblem {
                liveActivityHint
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Mode 1 counts down, mode 2 counts up.
    private func displayedClock(for session: Session) -> String {
        if let planned = session.plannedDuration {
            return max(0, planned - store.activeElapsed).clockText()
        }
        return store.activeElapsed.clockText()
    }

    private func caption(for session: Session) -> String {
        switch session.mode {
        case .countdown:
            let planned = session.plannedDuration ?? 0
            return "倒计时 · 共 \(planned.durationTextCompact())"
        case .stopwatch:
            let sent = session.reminderDates().filter { $0 <= Date() }.count
            return "正向计时 · 20 分钟网格 · 已提醒 \(sent) 次"
        }
    }

    /// Tells the user why the lock screen is empty (Settings toggle, or an API failure).
    @ViewBuilder
    private var liveActivityHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
            switch store.liveActivityState {
            case .disabled:
                Text("实时活动已关闭，锁屏不显示计时")
                    .font(.caption2)
                Spacer(minLength: 0)
                Button("去开启") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption2.weight(.medium))
            case .failed(let message):
                Text("锁屏计时未启动（\(message)）")
                    .font(.caption2)
            default:
                EmptyView()
            }
        }
        .foregroundStyle(.orange)
    }

    // MARK: - Recent

    /// Last few records — a glance at "what was I just doing", not a full log.
    private var recentSection: some View {
        let recent = store.todaySegments
            .filter { $0.kind == .session }
            .suffix(3)
            .reversed()

        return VStack(alignment: .leading, spacing: 0) {
            if recent.isEmpty {
                Text("今天还没有记录")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("最近")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)

                ForEach(Array(recent)) { segment in
                    HStack(spacing: 10) {
                        Text(segment.start.timeText())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)

                        Circle()
                            .fill(Color.forTitle(segment.session?.title ?? ""))
                            .frame(width: 6, height: 6)

                        Text(segment.session?.title ?? "—")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(segment.duration.durationTextCompact())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 7)

                    if segment.id != Array(recent).last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(spacing: 14) {
            TextField("要做什么？", text: $draftTitle)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focusedField, equals: .title)
                .onSubmit(startSession)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            focusedField == .title
                                ? Color.accentColor.opacity(0.6)
                                : Color.secondary.opacity(0.18),
                            lineWidth: 1
                        )
                )

            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("0", text: $minutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit())
                    .focused($focusedField, equals: .duration)
                    .frame(width: 60)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                focusedField == .duration
                                    ? Color.accentColor.opacity(0.6)
                                    : Color.secondary.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: minutesText) { _, value in
                        // Digits only, and never let the field grow unbounded.
                        let filtered = String(value.filter(\.isNumber).prefix(4))
                        if filtered != value { minutesText = filtered }
                    }

                Text("分钟")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(isTimed ? "到点提醒一次，随即结束记录" : "0 = 不定时 · 每 20 分钟提醒一次")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: startSession) {
                Label("开始记录", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canStart ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canStart)
        }
    }

    private func startSession() {
        guard canStart else { return }
        store.start(title: draftTitle, plannedDuration: isTimed ? plannedSeconds : nil)
        draftTitle = ""
        focusedField = nil
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if store.todaySummary.recorded > 0 {
                Text("今天已记录 \(store.todaySummary.recorded.durationTextCompact())")
                    .monospacedDigit()
            } else {
                Text("今天还没有记录")
            }
            Text("·")
            Text("左右滑动切换")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
