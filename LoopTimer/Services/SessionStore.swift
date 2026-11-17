//
//  SessionStore.swift
//  LoopTimer
//
//  The single source of truth for recorded time.
//
//  Responsibilities:
//   • start / stop sessions (a new task silently takes over the running one)
//   • keep exactly one active session, auto-ending mode 1 and cutting at midnight
//   • reconcile after a relaunch / reboot (all logic is timestamp based)
//   • publish the current day as ready-to-render segments + summary
//
//  Nothing here needs the process to stay alive: every duration is recomputed
//  from `startedAt`, so backgrounding, being killed, or rebooting cannot corrupt
//  a record. The ticker only exists to refresh the on-screen number.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var active: Session?
    @Published private(set) var activeElapsed: TimeInterval = 0
    /// The day currently being displayed (start of day).
    @Published private(set) var day: Date = Calendar.current.startOfDay(for: .now)
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var segments: [DaySegment] = []
    @Published private(set) var summary: DaySummary = .empty
    /// Today, always — regardless of which day the detail page is browsing.
    /// The timer page must never be tied to the browsed date.
    @Published private(set) var todaySegments: [DaySegment] = []
    @Published private(set) var todaySummary: DaySummary = .empty
    /// Mirrors LiveActivityService.State so the UI can explain a missing lock screen entry.
    @Published private(set) var liveActivityState: LiveActivityService.State = .idle

    /// Fired when a countdown session ends by itself (used for the in-app chime).
    var onAutoComplete: ((Session) -> Void)?
    /// Fired when a mode-2 grid point is crossed while the app is in the foreground
    /// (the notification banner is suppressed in-app, so the chime is played here).
    var onReminderDue: ((Session, Int) -> Void)?

    private var context: ModelContext?
    private var ticker: Timer?
    /// Highest grid index already announced for the active session.
    private var lastReminderIndex = 0
    private let liveActivity = LiveActivityService()

    private init() {
        liveActivity.onStateChange = { [weak self] state in
            self?.liveActivityState = state
        }

        // Posted by StopTimerIntent, which runs in this process.
        NotificationCenter.default.addObserver(
            forName: .stopTimerIntent,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopActive()
            }
        }
    }

    // MARK: - Setup

    func attach(context: ModelContext) {
        self.context = context
        reconcile()
    }

    /// Attaches lazily. Intents can be performed from a background launch, where
    /// the view hierarchy (and therefore any earlier attach) may not exist yet.
    func attachIfNeeded() {
        guard context == nil else { return }
        attach(context: Persistence.shared.mainContext)
    }

    var isAttached: Bool { context != nil }

    // MARK: - Commands

    /// Starts a session. Any running session is silently closed at `now` (superseded).
    @discardableResult
    func start(title: String, plannedDuration: TimeInterval?, now: Date = .now) -> Session? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        closeActive(at: now, reason: .superseded)

        let session = Session(title: trimmed, startedAt: Date(), plannedDuration: plannedDuration)
        // Count from the exact moment the caller asked for.
        session.startedAt = now
        context?.insert(session)
        save()

        active = session
        activeElapsed = 0
        lastReminderIndex = 0
        // NOTE: deliberately does not touch `day` — the detail page keeps whatever
        // date the user is browsing.
        startTicking()
        refresh(now: now)

        Task { await SessionReminderScheduler.shared.schedule(for: session, now: now) }
        liveActivity.sync(with: session)
        return session
    }

    /// Starts and waits for the reminders to be registered.
    /// App Intents get suspended as soon as `perform()` returns, so the scheduling
    /// must not be left to a detached task.
    @discardableResult
    func startAndSchedule(
        title: String,
        plannedDuration: TimeInterval?,
        now: Date = .now
    ) async -> Session? {
        guard let session = start(title: title, plannedDuration: plannedDuration, now: now) else {
            return nil
        }
        await SessionReminderScheduler.shared.schedule(for: session, now: now)
        return session
    }

    /// Stops the running session, recording the actual duration.
    func stopActive(now: Date = .now) {
        guard active != nil else { return }
        closeActive(at: now, reason: .stopped)
        refresh(now: now)
    }

#if DEBUG
    /// Inserts a finished record (debug only) — used to exercise export escaping.
    func insertDebugSession(title: String, startedAt: Date, endedAt: Date) {
        guard let context else { return }
        let session = Session(title: title, startedAt: startedAt, plannedDuration: nil)
        session.endedAt = endedAt
        session.endReason = .stopped
        context.insert(session)
        save()
        refresh()
    }
    /// Diagnostics for `-dumpLiveActivity`.
    func liveActivityDebugReport() async -> String {
        await liveActivity.debugReport()
    }
#endif

    /// Every record ever, oldest first (used by "export everything").
    func allSessions() -> [Session] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Re-attempts the lock-screen projection. `Activity.request` only succeeds
    /// while the app is active, so this is called again when the scene becomes
    /// active (the launch-time `reconcile()` may be too early).
    func syncLiveActivity() {
        liveActivity.sync(with: active)
    }

    func selectDay(_ date: Date) {
        day = Calendar.current.startOfDay(for: date)
        refresh()
    }

    func goToToday() {
        selectDay(.now)
    }

    // MARK: - Reconciliation

    /// Brings persisted state back in line with reality. Safe to call any time,
    /// idempotent, and the only thing that needs to run at launch.
    func reconcile(now: Date = .now) {
        guard let context else { return }

        // Only follow the calendar rollover if the user was already looking at
        // today — browsing a past day must not be yanked back.
        let wasOnToday = Calendar.current.isDateInToday(day)

        let all = (try? context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
        )) ?? []

        // Keep only the newest open session; anything older is a stale duplicate.
        var open = all.filter { $0.endedAt == nil }
        if open.count > 1 {
            let newest = open[open.count - 1]
            for stale in open.dropLast() {
                let cut = min(newest.startedAt, stale.dayEnd)
                stale.endedAt = cut
                stale.endReason = cut >= stale.dayEnd ? .midnightCut : .superseded
            }
            open = [newest]
        }

        var stillOpen: [Session] = []
        var autoCompleted: [Session] = []
        for session in open {
            if let end = session.autoEnd(asOf: now) {
                session.endedAt = end.date
                session.endReason = end.reason
                if end.reason == .completed { autoCompleted.append(session) }
            } else {
                stillOpen.append(session)
            }
        }
        save()

        active = stillOpen.last
        if let active {
            activeElapsed = active.duration(asOf: now)
            lastReminderIndex = reminderIndex(for: active, now: now)
            startTicking()
            // Idempotent by construction: same identifiers, same grid.
            Task { await SessionReminderScheduler.shared.schedule(for: active, now: now) }
        } else {
            stopTicking()
            activeElapsed = 0
            lastReminderIndex = 0
        }

        for session in autoCompleted {
            Task { await SessionReminderScheduler.shared.cancel(for: session) }
        }

        // The lock screen is a projection of the store, so it is re-synced here
        // rather than restored from an activity on launch.
        liveActivity.sync(with: active)

        // Anything still pending for a session that is no longer running is dead
        // weight (the process may not have been alive to cancel it).
        Task { await SessionReminderScheduler.shared.sweepStaleReminders(keeping: active?.id) }

        // If the day rolled over while we were away, follow it.
        let today = Calendar.current.startOfDay(for: now)
        if wasOnToday && day != today {
            day = today
        }
        refresh(now: now)

        for session in autoCompleted {
            onAutoComplete?(session)
        }
    }

    func refresh(now: Date = .now) {
        guard context != nil else { return }

        let dayStart = Calendar.current.startOfDay(for: day)
        sessions = fetchSessions(on: dayStart)
        segments = DayComposer.segments(sessions: sessions, day: dayStart, now: now)
        summary = DayComposer.summary(segments: segments, day: dayStart)

        let todayStart = Calendar.current.startOfDay(for: now)
        if todayStart == dayStart {
            // The detail page is already showing today — reuse the work.
            todaySegments = segments
            todaySummary = summary
        } else {
            let todaySessions = fetchSessions(on: todayStart)
            todaySegments = DayComposer.segments(sessions: todaySessions, day: todayStart, now: now)
            todaySummary = DayComposer.summary(segments: todaySegments, day: todayStart)
        }
    }

    private func fetchSessions(on dayStart: Date) -> [Session] {
        guard let context else { return [] }
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { session in
                session.startedAt >= dayStart && session.startedAt < dayEnd
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

#if DEBUG
    /// Fills today with a plausible day so the timeline can be developed and
    /// eyeballed without waiting 8 hours. Launch with `-seedDemoDay` once.
    func seedDemoDayIfRequested(now: Date = .now) {
        guard CommandLine.arguments.contains("-seedDemoDay"), let context else { return }
        let flag = "didSeedDemoDay"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)

        let dayStart = Calendar.current.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart) ?? dayStart
        }
        func seed(_ title: String, _ from: Date, _ to: Date?,
                  planned: TimeInterval? = nil, reason: SessionEndReason? = nil) {
            let session = Session(title: title, startedAt: from, plannedDuration: planned)
            session.endedAt = to
            session.endReason = reason
            context.insert(session)
        }

        // A morning → afternoon day, with one stopwatch still running.
        seed("写作", at(8, 12), at(8, 37))
        seed("早饭", at(8, 45), at(9, 10))
        seed("健身", at(9, 19), at(10, 59))
        seed("写代码", at(11, 2), at(13, 7))
        seed("午饭", at(13, 20), at(13, 52))
        seed("会议", at(14, 5), at(14, 50))
        seed("读书", at(15, 10), at(15, 38), planned: 20 * 60, reason: .stopped)
        seed("写代码", now.addingTimeInterval(-17 * 60), nil)

        save()
        reconcile(now: now)
    }
#endif

    // MARK: - Private

    private func closeActive(at date: Date, reason: SessionEndReason) {
        guard let session = active else { return }
        let cut = min(date, session.dayEnd)
        session.endedAt = cut
        session.endReason = cut >= session.dayEnd ? .midnightCut : reason
        save()
        active = nil
        activeElapsed = 0
        lastReminderIndex = 0
        stopTicking()
        Task { await SessionReminderScheduler.shared.cancel(for: session) }
        liveActivity.sync(with: nil)
    }

    /// The grid index the session has already reached at `now`.
    private func reminderIndex(for session: Session, now: Date) -> Int {
        guard session.mode == .stopwatch,
              let interval = session.reminderInterval,
              interval > 0 else { return 0 }
        let elapsed = session.duration(asOf: now)
        return min(RecordDefaults.maxReminders, Int(elapsed / interval))
    }

    private func save() {
        do {
            try context?.save()
        } catch {
            print("SessionStore: save failed — \(error)")
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick(now: Date = .now) {
        guard let session = active else {
            stopTicking()
            return
        }

        activeElapsed = session.duration(asOf: now)

        // Mode 2: announce a grid point that was just crossed while in-app
        // (the notification banner is suppressed in the foreground).
        if session.mode == .stopwatch {
            let index = reminderIndex(for: session, now: now)
            if index > lastReminderIndex {
                lastReminderIndex = index
                onReminderDue?(session, index)
            }
        }

        if let end = session.autoEnd(asOf: now) {
            session.endedAt = end.date
            session.endReason = end.reason
            save()
            active = nil
            activeElapsed = 0
            lastReminderIndex = 0
            stopTicking()

            // Midnight cut rolls the detail page onto the new day — but only if it
            // was already following today.
            if end.reason == .midnightCut, Calendar.current.isDateInToday(day) {
                day = Calendar.current.startOfDay(for: now)
            }
            refresh(now: now)
            Task { await SessionReminderScheduler.shared.cancel(for: session) }
            liveActivity.sync(with: nil)
            if end.reason == .completed {
                onAutoComplete?(session)
            }
            return
        }

        // A new day can start while a stopwatch runs; the session is cut by the
        // line above, but guard the display against a stale day anyway.
        let today = Calendar.current.startOfDay(for: now)
        if today != day && active == nil {
            day = today
            refresh(now: now)
        }
    }
}
