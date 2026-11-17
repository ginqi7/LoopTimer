//
//  LoopTimerLiveActivity.swift
//  LoopTimerWidgetExtension
//
//  Lock screen / Dynamic Island projection of the running session.
//
//  The clock is rendered by `Text(timerInterval:)`, so the system ticks it without
//  the app sending updates. Countdown sessions count down to `plannedEnd`,
//  stopwatch sessions count up from `startedAt`.
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import Foundation

// MARK: - Stop intent

/// Runs in the *app* process (LiveActivityIntent), so it can only talk to the app
/// through NotificationCenter — the widget target does not compile SessionStore.
struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止记录"
    static var description = IntentDescription("停止当前任务并记录")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .stopTimerIntent, object: nil)
        }
        return .result()
    }
}

extension Notification.Name {
    static let stopTimerIntent = Notification.Name("stopTimerIntent")
}

// MARK: - Widget

@main
struct LoopTimerWidgets: WidgetBundle {
    var body: some Widget {
        LoopTimerLiveActivity()
    }
}

struct LoopTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    clock(context: context)
                        .font(.title3.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    stopButton
                        .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                compactClock(context: context)
            } minimal: {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Lock screen

    private func lockScreenView(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.blue)
                    .frame(width: 7, height: 7)

                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(caption(context: context))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                clock(context: context)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .monospacedDigit()

                Spacer(minLength: 0)

                stopButton
            }
        }
        .padding()
        .activityBackgroundTint(Color(.systemGray6).opacity(0.85))
        .activitySystemActionForegroundColor(.primary)
    }

    private var stopButton: some View {
        Button(intent: StopTimerIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.red)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clock

    @ViewBuilder
    private func clock(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        if let plannedEnd = context.attributes.plannedEnd {
            Text(timerInterval: context.attributes.startedAt...max(plannedEnd, context.attributes.startedAt), countsDown: true)
        } else {
            Text(context.attributes.startedAt, style: .timer)
        }
    }

    @ViewBuilder
    private func compactClock(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        if let plannedEnd = context.attributes.plannedEnd {
            Text(timerInterval: context.attributes.startedAt...max(plannedEnd, context.attributes.startedAt), countsDown: true)
                .font(.caption2.monospacedDigit())
        } else {
            Text(context.attributes.startedAt, style: .timer)
                .font(.caption2.monospacedDigit())
        }
    }

    private func caption(context: ActivityViewContext<TimerActivityAttributes>) -> String {
        context.attributes.plannedEnd == nil ? "正向计时" : "倒计时"
    }
}
