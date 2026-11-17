//
//  DaySegment.swift
//  LoopTimer
//
//  A day is composed of three kinds of segments laid end to end:
//    .session — recorded activity
//    .gap     — elapsed time with nothing recorded
//    .future  — today's remaining hours (not yet lived)
//
//  Composing gaps as first-class segments means the timeline view never has to
//  do time arithmetic in the UI layer: it is a plain ForEach over the segments.
//

import Foundation

struct DaySegment: Identifiable {
    enum Kind {
        case session
        case gap
        case future
    }

    let id: String
    let kind: Kind
    let start: Date
    let end: Date
    /// Non-nil only for `.session`.
    let session: Session?
    /// Highlighted ending for `.session` (midnight cut / taken over / early stop).
    let endReason: SessionEndReason?

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    var isActive: Bool {
        session?.isActive == true
    }
}

struct TitleTotal: Identifiable {
    var id: String { title }
    let title: String
    let duration: TimeInterval
    let count: Int
}

struct DaySummary {
    let day: Date
    let recorded: TimeInterval
    let gap: TimeInterval
    let sessionCount: Int
    let longest: DaySegment?
    let byTitle: [TitleTotal]

    static let empty = DaySummary(
        day: Date(),
        recorded: 0,
        gap: 0,
        sessionCount: 0,
        longest: nil,
        byTitle: []
    )
}

enum DayComposer {
    /// Lays out a day as contiguous segments from 00:00 to 24:00.
    static func segments(sessions: [Session], day: Date, now: Date = .now) -> [DaySegment] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        // Everything up to `cutoff` has already happened.
        let cutoff = min(max(now, dayStart), dayEnd)

        var result: [DaySegment] = []
        var cursor = dayStart

        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let sessionEnd = min(session.endedAt ?? min(now, session.dayEnd), dayEnd)
            let sessionStart = max(session.startedAt, dayStart)
            guard sessionEnd > sessionStart else { continue }

            // Never let a session start before the previous segment ended.
            let start = max(sessionStart, cursor)
            guard sessionEnd > start else { continue }

            if start > cursor {
                result.append(gap(from: cursor, to: start))
            }

            result.append(
                DaySegment(
                    id: "session-\(session.id.uuidString)-\(Int(start.timeIntervalSince1970))",
                    kind: .session,
                    start: start,
                    end: sessionEnd,
                    session: session,
                    endReason: session.endReason
                )
            )
            cursor = sessionEnd
        }

        if cursor < cutoff {
            result.append(gap(from: cursor, to: cutoff))
        }
        if cutoff < dayEnd {
            result.append(
                DaySegment(
                    id: "future-\(Int(cutoff.timeIntervalSince1970))",
                    kind: .future,
                    start: cutoff,
                    end: dayEnd,
                    session: nil,
                    endReason: nil
                )
            )
        }
        return result
    }

    static func summary(segments: [DaySegment], day: Date) -> DaySummary {
        let sessionSegments = segments.filter { $0.kind == .session }
        let recorded = sessionSegments.reduce(0) { $0 + $1.duration }
        let gap = segments.filter { $0.kind == .gap }.reduce(0) { $0 + $1.duration }

        var totals: [String: (duration: TimeInterval, count: Int)] = [:]
        for segment in sessionSegments {
            guard let title = segment.session?.title else { continue }
            let existing = totals[title] ?? (0, 0)
            totals[title] = (existing.duration + segment.duration, existing.count + 1)
        }
        let byTitle = totals
            .map { TitleTotal(title: $0.key, duration: $0.value.duration, count: $0.value.count) }
            .sorted { $0.duration > $1.duration }

        return DaySummary(
            day: day,
            recorded: recorded,
            gap: gap,
            sessionCount: sessionSegments.count,
            longest: sessionSegments.max { $0.duration < $1.duration },
            byTitle: byTitle
        )
    }

    private static func gap(from start: Date, to end: Date) -> DaySegment {
        DaySegment(
            id: "gap-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))",
            kind: .gap,
            start: start,
            end: end,
            session: nil,
            endReason: nil
        )
    }
}
