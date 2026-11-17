//
//  SessionReminderScheduler.swift
//  LoopTimer
//
//  Turns a session into concrete local notifications.
//
//  Everything is derived from `session.startedAt`, never from "when we happened
//  to schedule". That makes scheduling idempotent: re-running it after a kill,
//  a reboot, or a relaunch simply replaces the pending requests under the same
//  identifiers, so the 20-minute grid can never drift.
//
//  Why one-shots instead of a single repeating trigger: the reminder must say how
//  long the task has been running ("已经 1 小时 20 分钟了"), and a repeating
//  trigger's text is fixed at scheduling time. The cost is one pending request
//  per reminder, capped at RecordDefaults.maxReminders (10), which is far inside
//  the system's 64-pending limit.
//
//  The schedule itself is produced by the pure `plan(for:now:)`; `schedule(for:)`
//  only hands those plans to the system. That keeps the interesting logic
//  testable and identical to what actually gets registered.
//

import Foundation
import UserNotifications

/// One notification that should exist.
struct ReminderPlan {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String?
}

@MainActor
final class SessionReminderScheduler {
    static let shared = SessionReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private let soundDefaultsKey = "selectedChimeSound"

    private init() {}

    // MARK: - Identifiers

    private func base(_ session: Session) -> String {
        "session-\(session.id.uuidString)"
    }

    /// Deterministic, so cancelling never needs to query the system.
    private func allIdentifiers(for sessionID: UUID) -> [String] {
        let base = "session-\(sessionID.uuidString)"
        var ids = ["\(base)-end"]
        ids.append(contentsOf: (1...RecordDefaults.maxReminders).map { "\(base)-reminder-\($0)" })
        return ids
    }

    // MARK: - Planning (pure)

    /// The complete set of notifications a session should have.
    func plan(for session: Session, now: Date = .now) -> [ReminderPlan] {
        guard session.endedAt == nil else { return [] }

        switch session.mode {
        case .countdown:
            return countdownPlan(for: session, now: now)
        case .stopwatch:
            return gridPlan(for: session, now: now)
        }
    }

    /// Mode 1: exactly one notification, at the moment the session really ends
    /// (clamped to midnight, so a countdown that would cross 00:00 reports the
    /// truncated duration rather than the planned one).
    private func countdownPlan(for session: Session, now: Date) -> [ReminderPlan] {
        guard let planned = session.plannedDuration, planned > 0 else { return [] }
        let endDate = min(session.startedAt.addingTimeInterval(planned), session.dayEnd)
        guard endDate > now else { return [] }

        let recorded = endDate.timeIntervalSince(session.startedAt)
        return [
            ReminderPlan(
                identifier: "\(base(session))-end",
                fireDate: endDate,
                title: "「\(session.title)」时间到了",
                body: "已记录 \(recorded.durationText())"
            )
        ]
    }

    /// Mode 2: the 20-minute grid, capped at `maxReminders`, never past midnight.
    private func gridPlan(for session: Session, now: Date) -> [ReminderPlan] {
        guard let interval = session.reminderInterval, interval > 0 else { return [] }

        return (1...RecordDefaults.maxReminders).compactMap { index in
            let fireDate = session.startedAt.addingTimeInterval(Double(index) * interval)
            guard fireDate > now, fireDate < session.dayEnd else { return nil }

            let accumulated = Double(index) * interval
            return ReminderPlan(
                identifier: "\(base(session))-reminder-\(index)",
                fireDate: fireDate,
                title: "「\(session.title)」已经 \(accumulated.durationText())了",
                body: nil
            )
        }
    }

    // MARK: - Registration

    func schedule(for session: Session, now: Date = .now) async {
        guard session.endedAt == nil else { return }
        await cancel(for: session)

        let items = plan(for: session, now: now)
        guard !items.isEmpty else { return }
        let threadIdentifier = base(session)

        let before = await authorizationStatus()
        switch before {
        case .denied:
            // Nothing to do until the user re-enables notifications in Settings.
            return
        case .notDetermined:
            // Register first so a session that is already allowed never loses its
            // first reminder to the permission alert, then ask and retry once.
            await register(items, threadIdentifier: threadIdentifier, sessionID: session.id)
            await requestAuthorizationIfNeeded()
            let after = await authorizationStatus()
            if after != .notDetermined && after != .denied {
                await register(items, threadIdentifier: threadIdentifier, sessionID: session.id)
            }
        default:
            await register(items, threadIdentifier: threadIdentifier, sessionID: session.id)
        }
    }

    private func register(
        _ items: [ReminderPlan],
        threadIdentifier: String,
        sessionID: UUID
    ) async {
        for item in items {
            await add(item, threadIdentifier: threadIdentifier, sessionID: sessionID)
        }
    }

    /// Removes every `session-*` request that does not belong to the running
    /// session. Needed because a session can end while the process is dead (0 点
    /// 截断、被 reconcile 去重), and nobody would be left to cancel its reminders.
    func sweepStaleReminders(keeping activeID: UUID?) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "session-"

        let stale = pending.map(\.identifier).filter { identifier in
            guard identifier.hasPrefix(prefix) else { return false }
            let rest = identifier.dropFirst(prefix.count)
            guard let id = UUID(uuidString: String(rest.prefix(36))) else { return true }
            return id != activeID
        }

        guard !stale.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        center.removeDeliveredNotifications(withIdentifiers: stale)
        print("SessionReminderScheduler: swept \(stale.count) stale reminders")
    }

    /// Removes every reminder belonging to the session (fires on stop, takeover,
    /// auto-end and midnight cut).
    func cancel(for session: Session) async {
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: session.id))
        center.removeDeliveredNotifications(withIdentifiers: allIdentifiers(for: session.id))
    }

    func cancel(forSessionID id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: id))
        center.removeDeliveredNotifications(withIdentifiers: allIdentifiers(for: id))
    }

    // MARK: - Building blocks

    private var currentSoundName: String {
        UserDefaults.standard.string(forKey: soundDefaultsKey) ?? ChimeSound.defaultSound.id
    }

    private func add(_ item: ReminderPlan, threadIdentifier: String, sessionID: UUID) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        if let body = item.body { content.body = body }
        content.threadIdentifier = threadIdentifier
        content.userInfo = ["sessionID": sessionID.uuidString]
        // Time Sensitive needs the matching entitlement to be honoured; without it
        // iOS degrades this to a normal notification, which is harmless.
        content.interruptionLevel = .timeSensitive

        if let soundFile = cafFileName(for: currentSoundName) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundFile))
        } else {
            content.sound = .default
        }

        let interval = max(1, item.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("SessionReminderScheduler: failed to add \(item.identifier) — \(error)")
        }
    }

    private func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func requestAuthorizationIfNeeded() async {
        guard await authorizationStatus() == .notDetermined else { return }
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
#if DEBUG
        // Lets the simulator grant silently so the registration path is testable.
        if CommandLine.arguments.contains("-provisionalAuth") {
            options.insert(.provisional)
        }
#endif
        _ = try? await center.requestAuthorization(options: options)
    }

    private func cafFileName(for soundName: String) -> String? {
        if let sound = ChimeSound.allSounds.first(where: { $0.id == soundName }) {
            return "\(sound.fileName).\(sound.fileExtension)"
        }
        return "\(ChimeSound.defaultSound.fileName).\(ChimeSound.defaultSound.fileExtension)"
    }

    // MARK: - Diagnostics

#if DEBUG
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Writes the *planned* schedule plus the live authorization state to the
    /// app's tmp directory, so the whole thing can be inspected without needing
    /// a notification permission grant in the simulator.
    func dumpForDebug(session: Session?, now: Date = .now) async {
        let settings = await center.notificationSettings()
        let status: String
        switch settings.authorizationStatus {
        case .notDetermined: status = "notDetermined"
        case .denied: status = "denied"
        case .authorized: status = "authorized"
        case .provisional: status = "provisional"
        case .ephemeral: status = "ephemeral"
        @unknown default: status = "unknown"
        }

        var lines = ["authorization=\(status)"]

        if let session {
            lines.append("session=\(session.title) mode=\(session.mode) start=\(Self.clockFormatter.string(from: session.startedAt))")
            let plan = plan(for: session, now: now)
            lines.append("planned=\(plan.count)")
            for item in plan {
                lines.append(
                    [
                        item.identifier.components(separatedBy: "-").suffix(2).joined(separator: "-"),
                        Self.clockFormatter.string(from: item.fireDate),
                        item.title,
                        item.body ?? ""
                    ].joined(separator: " | ")
                )
            }
        } else {
            lines.append("session=nil")
        }

        let pending = await center.pendingNotificationRequests()
        lines.append("registered=\(pending.count)")

        let text = lines.joined(separator: "\n")
        try? text.write(
            to: URL.temporaryDirectory.appendingPathComponent("reminders.txt"),
            atomically: true,
            encoding: .utf8
        )
        print("SessionReminderScheduler dump:\n\(text)")
    }
#endif
}
