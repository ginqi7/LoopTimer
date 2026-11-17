//
//  DayPageView.swift
//  LoopTimer
//
//  Page 2 — "今天": the day's summary plus the 24-hour vertical canvas.
//  Read-only: recording is started and stopped on the timer page.
//

import SwiftUI

struct DayPageView: View {
    @ObservedObject var store: SessionStore
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Divider().opacity(0.4)

            DayTimelineView(segments: store.segments, day: store.day)
        }
    }

    private var summaryBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if store.summary.recorded > 0 {
                Text("已记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(store.summary.recorded.durationTextCompact())
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("还没有记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer(minLength: 6)

            if store.summary.gap > 0 {
                Text("空档 \(store.summary.gap.durationTextCompact())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("导出")
        }
        .padding(.top, 4)
    }
}
