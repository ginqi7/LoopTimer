//
//  Session.swift
//  LoopTimer
//
//  One recorded activity — "a thing I did today".
//
//  Design rules baked in here (agreed spec):
//   • plannedDuration == nil  → mode 2 (stopwatch, 20-minute reminder grid)
//   • plannedDuration != nil  → mode 1 (countdown, single reminder, auto end)
//   • duration is ALWAYS derived from startedAt/endedAt. Never accumulated.
//   • a session never crosses midnight: it is cut at the end of its start day.
//

import Foundation
import SwiftData

/// Why a session stopped being "active".
enum SessionEndReason: String, Codable {
    case completed      // mode 1 reached its planned duration
    case stopped        // user tapped stop
    case midnightCut    // hit 00:00 of the next day
    case superseded     // a new task silently took over
}

enum SessionMode {
    case countdown      // mode 1
    case stopwatch      // mode 2
}

enum RecordDefaults {
    /// Fixed 20-minute reminder grid for mode 2 (the UI hard-codes it, the field can change).
    static let reminderInterval: TimeInterval = 20 * 60
    /// Never schedule more than this many reminders for one session.
    static let maxReminders: Int = 10
}

@Model
final class Session {
    var id: UUID = UUID()
    var title: String = ""
    /// nil → stopwatch mode.
    var plannedDuration: TimeInterval?
    /// Mode 2 only: seconds between reminders (default 20 min, kept adjustable).
    var reminderInterval: TimeInterval?
    var startedAt: Date = Date()
    /// nil → still running.
    var endedAt: Date?
    /// Raw value of SessionEndReason; stored as String for SwiftData friendliness.
    var endReasonRaw: String?

    init(title: String, startedAt: Date = .now, plannedDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.title = title
        self.startedAt = startedAt
        self.plannedDuration = plannedDuration
        self.reminderInterval = plannedDuration == nil ? RecordDefaults.reminderInterval : nil
        self.endedAt = nil
        self.endReasonRaw = nil
    }
}

// MARK: - Derived values

extension Session {
    var mode: SessionMode {
        plannedDuration == nil ? .stopwatch : .countdown
    }

    var isActive: Bool {
        endedAt == nil
    }

    var endReason: SessionEndReason? {
        get { endReasonRaw.flatMap(SessionEndReason.init(rawValue:)) }
        set { endReasonRaw = newValue?.rawValue }
    }

    /// The day this session belongs to, decided by its start time.
    var dayStart: Date {
        Calendar.current.startOfDay(for: startedAt)
    }

    /// 00:00 that terminates this session.
    var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
    }

    /// Mode 1 end moment, clamped to midnight.
    var plannedEnd: Date? {
        guard let plannedDuration else { return nil }
        return min(startedAt.addingTimeInterval(plannedDuration), dayEnd)
    }

    /// Elapsed up to `now` (or up to the recorded end). Clamped to the start day.
    func duration(asOf now: Date = .now) -> TimeInterval {
        let end = endedAt ?? min(now, dayEnd)
        return max(0, end.timeIntervalSince(startedAt))
    }

    /// The reminder grid: startedAt + k·interval for k = 1...maxReminders, before midnight.
    /// Stateless on purpose — recomputing from `startedAt` is idempotent after a relaunch
    /// and keeps the grid perfectly locked (no phase drift).
    func reminderDates() -> [Date] {
        guard let reminderInterval, reminderInterval > 0 else { return [] }
        return (1...RecordDefaults.maxReminders).compactMap { k in
            let date = startedAt.addingTimeInterval(Double(k) * reminderInterval)
            return date < dayEnd ? date : nil
        }
    }

    /// If this session should already be over by `now`, returns when and why.
    func autoEnd(asOf now: Date) -> (date: Date, reason: SessionEndReason)? {
        if now >= dayEnd {
            return (dayEnd, .midnightCut)
        }
        switch mode {
        case .countdown:
            guard let plannedEnd, now >= plannedEnd else { return nil }
            return plannedEnd >= dayEnd ? (dayEnd, .midnightCut) : (plannedEnd, .completed)
        case .stopwatch:
            return nil
        }
    }
}
