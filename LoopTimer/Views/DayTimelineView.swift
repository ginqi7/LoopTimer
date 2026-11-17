//
//  DayTimelineView.swift
//  LoopTimer
//
//  The 24-hour vertical canvas: 00:00 at the top, 24:00 at the bottom.
//  Nothing is trimmed — the whole day is always shown, so the gaps between
//  sessions are as visible as the sessions themselves.
//
//  Scale is fixed at 1 hour = 72pt (≈2.5 screens for a full day).
//
//  Layout note: segments are stacked in a real VStack whose row heights are the
//  durations, so layout position == time position. That is what makes
//  `scrollTo` land on the current time; `.offset` alone would not (offsets are
//  visual only). The "now" marker is a zero-height row in the same stack.
//
//  Time maps to the vertical axis, so a moment in time is a horizontal line —
//  which is why the mode-2 reminder grid is drawn as horizontal hairlines
//  inside a session block: each one is a reminder that actually fired.
//

import SwiftUI
import Combine

struct DayTimelineView: View {
    let segments: [DaySegment]
    let day: Date

    static let hourHeight: CGFloat = 72

    @State private var nowTick: Date = .now

    private var dayStart: Date {
        Calendar.current.startOfDay(for: day)
    }

    private var totalHeight: CGFloat {
        24 * Self.hourHeight
    }

    /// Points per second.
    private var scale: CGFloat {
        Self.hourHeight / 3600
    }

    private func height(for duration: TimeInterval) -> CGFloat {
        CGFloat(duration) * scale
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        enum Content {
            case segment(DaySegment)
            case now
        }
        let id: String
        let content: Content
    }

    private var rows: [Row] {
        var result: [Row] = []
        var markerPlaced = false
        for segment in segments {
            // The `.future` segment starts exactly at the store's `now` (DayComposer
            // splits it there), so it is the authoritative boundary to anchor the
            // "now" marker to. Comparing `segment.end > nowTick` instead is wrong:
            // nowTick is view state and can be older than the store's `now`, which
            // put the marker at the very top of the day.
            if isToday && !markerPlaced && segment.kind == .future {
                result.append(Row(id: "now-marker", content: .now))
                markerPlaced = true
            }
            result.append(Row(id: segment.id, content: .segment(segment)))
        }
        if isToday && !markerPlaced {
            result.append(Row(id: "now-marker", content: .now))
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    hourGutter
                    canvas
                }
                .padding(.top, 10)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
            }
            .overlay(alignment: .bottomTrailing) {
                if isToday {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("now-marker", anchor: .center)
                        }
                    } label: {
                        Label("现在", systemImage: "arrow.down.to.line.compact")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
                }
            }
            .task {
                // Scroll targets only exist after the first layout pass.
                try? await Task.sleep(for: .milliseconds(120))
                proxy.scrollTo("now-marker", anchor: .center)
#if DEBUG
                if CommandLine.arguments.contains("-dumpTimeline") { dumpTimeline() }
#endif
            }
            .onChange(of: day) { _, _ in
                proxy.scrollTo("now-marker", anchor: .center)
            }
            .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { date in
                nowTick = date
            }
        }
    }

    // MARK: - Hour gutter

    private var hourGutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, height: Self.hourHeight, alignment: .top)
                    .offset(y: -5)
            }
        }
        .padding(.leading, 10)
    }

    // MARK: - Canvas

    private var canvas: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                switch row.content {
                case .segment(let segment):
                    segmentRow(segment)
                        .frame(height: height(for: segment.duration))
                        .id(segment.id)
                case .now:
                    nowRow
                        .frame(height: 0)
                        .id("now-marker")
                }
            }
        }
        .frame(maxWidth: .infinity)
        // Hour rulings, drawn over the stack (visual only — never used as targets).
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0...24, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(hour % 6 == 0 ? 0.16 : 0.07))
                        .frame(height: hour % 6 == 0 ? 1 : 0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: CGFloat(hour) * Self.hourHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Segment rows

    @ViewBuilder
    private func segmentRow(_ segment: DaySegment) -> some View {
        switch segment.kind {
        case .session:
            sessionBlock(segment)
        case .gap:
            gapBlock(segment)
        case .future:
            futureBlock
        }
    }

    @ViewBuilder
    private func sessionBlock(_ segment: DaySegment) -> some View {
        let session = segment.session
        let color = Color.forTitle(session?.title ?? "")
        let h = height(for: segment.duration)

        // Reminders that actually fall inside this block (mode 2 only).
        let reminderTicks: [Date] = {
            guard let session, session.mode == .stopwatch else { return [] }
            return session.reminderDates().filter { date in
                let local = CGFloat(date.timeIntervalSince(segment.start)) * scale
                return local > 1 && local < h - 1
            }
        }()

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.16))

            ForEach(reminderTicks, id: \.self) { date in
                // A short dash on the right edge: reads as "a reminder fired here"
                // without looking like a divider across the block.
                Rectangle()
                    .fill(color.opacity(0.55))
                    .frame(width: 12, height: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(date.timeIntervalSince(segment.start)) * scale)
            }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4)

            if h >= 16 {
                HStack(spacing: 6) {
                    Text(session?.title ?? "—")
                        .font(.system(size: h >= 24 ? 12 : 10, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // The running block's right edge sits exactly under the "now"
                    // pill, so it shows no trailing label — the red line already
                    // says it is running.
                    if !segment.isActive {
                        Text(segment.duration.durationTextCompact())
                            .font(.system(size: h >= 24 ? 10 : 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(color.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, 0.5)
        // Too short to hold its own label: float a capsule beside it.
        .overlay(alignment: .topLeading) {
            if h < 16 {
                HStack(spacing: 4) {
                    Text(session?.title ?? "—")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                    Text(segment.duration.durationTextCompact())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                )
                .offset(x: 10, y: max(0, h / 2 - 8))
                .zIndex(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(session?.title ?? "")，\(segment.start.timeText()) 到 \(segment.end.timeText())，\(segment.duration.durationTextCompact())"
        )
    }

    private func gapBlock(_ segment: DaySegment) -> some View {
        let h = height(for: segment.duration)
        // Tall gaps get their label pinned near the top; a centred label can sit
        // outside the viewport when the gap spans many hours.
        let labelAtTop = h > 240

        return ZStack(alignment: labelAtTop ? .top : .center) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.05))

            if h >= 20 {
                Text("空档 \(segment.duration.durationTextCompact())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, labelAtTop ? 8 : 0)
            }
        }
        .padding(.vertical, 0.5)
    }

    private var futureBlock: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                Color.secondary.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
            .padding(.vertical, 0.5)
    }

#if DEBUG
    private func dumpTimeline() {
        var lines = ["nowTick=\(Self.clock.string(from: nowTick)) rows=\(rows.count)"]
        var total = 0.0
        for row in rows {
            switch row.content {
            case .now:
                lines.append("  [now-marker] h=0")
            case .segment(let segment):
                total += height(for: segment.duration)
                lines.append(
                    "  \(segment.kind) \(Self.clock.string(from: segment.start))->\(Self.clock.string(from: segment.end))"
                        + " d=\(Int(segment.duration))s h=\(Int(height(for: segment.duration)))"
                )
            }
        }
        lines.append("totalH=\(Int(total))")
        try? lines.joined(separator: "\n").write(
            to: URL.temporaryDirectory.appendingPathComponent("timeline.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
#endif

    // MARK: - Now marker

    private var nowRow: some View {
        Rectangle()
            .fill(Color.red.opacity(0.85))
            .frame(height: 1)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                    .offset(x: -2)
            }
            .overlay(alignment: .trailing) {
                Text(nowTick.timeText())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .fixedSize()
                    .offset(y: -11)
            }
    }
}

// MARK: - Title colours

extension Color {
    /// Stable colour per task name, so repeated tasks are recognisable in the day
    /// view without introducing a tag system.
    static func forTitle(_ title: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .teal, .orange, .pink, .green, .purple, .brown]
        guard !title.isEmpty else { return .gray }
        var hash: UInt64 = 5381
        for byte in title.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
