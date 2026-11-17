//
//  TimerActivityAttributes.swift
//  LoopTimer
//
//  Live Activity attributes for the running session.
//
//  Everything the lock screen needs is constant for the lifetime of the activity,
//  so it lives in the attributes: the widget derives the clock itself with
//  `Text(timerInterval:)`, which means **no update traffic at all** for a session.
//  ContentState is therefore intentionally empty.
//

import Foundation
import ActivityKit

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public init() {}
    }

    /// Identifies the session this activity projects (so the app can tell whether
    /// an existing activity still matches the running session).
    let sessionID: UUID
    let title: String
    let startedAt: Date
    /// Countdown target for mode 1; nil for a stopwatch (mode 2).
    let plannedEnd: Date?
}
