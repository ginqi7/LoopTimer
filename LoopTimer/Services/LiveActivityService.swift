//
//  LiveActivityService.swift
//  LoopTimer
//
//  Projects the running session onto the lock screen / Dynamic Island.
//
//  The activity is a *view* of the session, never the source of truth: records
//  live in SwiftData, so nothing needs restoring from an activity after a
//  relaunch. Because the widget renders the clock from `startedAt` with
//  `Text(timerInterval:)`, a session needs exactly one `Activity.request` and one
//  `end` — no updates in between.
//
//  Two rules learned the hard way:
//   1. `Activity<T>.activities` must be read **before** a new request is made.
//      Reading it inside a Task that was scheduled earlier means the freshly
//      created activity is already in the list, and ending the list ends it —
//      the activity then never shows up anywhere.
//   2. Requesting while the app is not in the foreground fails on device, so the
//      store re-syncs on `scenePhase == .active`.
//

import ActivityKit
import Foundation
import UIKit

@MainActor
final class LiveActivityService {

    enum State: Equatable {
        case idle
        case active
        case disabled      // user turned Live Activities off for this app
        case failed(String)

        var isProblem: Bool {
            switch self {
            case .disabled, .failed: return true
            case .idle, .active: return false
            }
        }
    }

    private(set) var state: State = .idle {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    var onStateChange: ((State) -> Void)?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Makes the lock screen reflect `session`, starting or replacing the activity
    /// as needed. Idempotent, so it is safe to call from `reconcile()` and again
    /// when the app becomes active.
    func sync(with session: Session?) {
        guard isSupported else {
            endAll()
            state = .disabled
            return
        }

        guard let session, session.endedAt == nil else {
            endAll()
            state = .idle
            return
        }

        // Re-attach to an activity that already represents this session (after a
        // relaunch, or when re-syncing on becoming active).
        if Activity<TimerActivityAttributes>.activities.contains(
            where: { $0.attributes.sessionID == session.id }
        ) {
            state = .active
            return
        }

        endStale(except: session.id)
        request(for: session)
    }

    func endAll() {
        // Snapshot first: any request made after this point must not be caught by
        // the asynchronous teardown.
        let existing = Activity<TimerActivityAttributes>.activities
        guard !existing.isEmpty else { return }
        Task {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Private

    private func endStale(except sessionID: UUID) {
        let stale = Activity<TimerActivityAttributes>.activities.filter {
            $0.attributes.sessionID != sessionID
        }
        guard !stale.isEmpty else { return }
        Task {
            for activity in stale {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func request(for session: Session) {
        // `Activity.request` only succeeds while the app is in the foreground.
        // Shortcuts can start a session from the background; the activity is then
        // created on the next `syncLiveActivity()` (scenePhase == .active).
        guard UIApplication.shared.applicationState == .active else {
            print("LiveActivityService: deferred until the app is active")
            return
        }

        let attributes = TimerActivityAttributes(
            sessionID: session.id,
            title: session.title,
            startedAt: session.startedAt,
            plannedEnd: session.plannedEnd
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(), staleDate: nil)
            )
            state = .active
            print("LiveActivityService: started for \(session.title)")
        } catch {
            state = .failed(Self.describe(error))
            print("LiveActivityService: request failed — \(error)")
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

#if DEBUG
    /// Diagnostics for `-dumpLiveActivity`.
    func debugReport() async -> String {
        let activities = Activity<TimerActivityAttributes>.activities
        var lines = [
            "enabled=\(isSupported)",
            "state=\(state)",
            "count=\(activities.count)"
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for activity in activities {
            lines.append(
                "id=\(activity.id) session=\(activity.attributes.sessionID.uuidString.prefix(8))"
                    + " title=\(activity.attributes.title)"
                    + " start=\(formatter.string(from: activity.attributes.startedAt))"
                    + " plannedEnd=\(activity.attributes.plannedEnd.map { formatter.string(from: $0) } ?? "-")"
                    + " ended=\(activity.activityState)"
            )
        }
        return lines.joined(separator: "\n")
    }
#endif
}
