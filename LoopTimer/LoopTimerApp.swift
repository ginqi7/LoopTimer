//
//  LoopTimerApp.swift
//  LoopTimer
//
//  App entry point and lifecycle management
//

import SwiftUI
import UIKit
import UserNotifications
import SwiftData

// AppDelegate to handle orientation locking and notification delegation
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    // Handle notifications when app is in foreground - suppress them since the app handles chimes
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Don't show notification banner or play sound when app is in foreground
        // The app will play the chime itself via AudioService
        completionHandler([])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

@main
struct LoopTimerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        SessionStore.shared.attach(context: Persistence.shared.mainContext)
#if DEBUG
        SessionStore.shared.seedDemoDayIfRequested()
        // `-dumpExport` writes the JSON/CSV for today into the sandbox so the exact
        // bytes (BOM, quoting, timestamps) can be inspected.
        if CommandLine.arguments.contains("-dumpExport") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let store = SessionStore.shared
                let day = store.day
                let daySessions = store.sessions
                let all = store.allSessions()
                let tmp = URL.temporaryDirectory
                try? Data(ExportService.jsonText(sessions: daySessions, scope: .day(day)).utf8)
                    .write(to: tmp.appendingPathComponent("export-day.json"))
                try? Data(ExportService.csvText(sessions: daySessions).utf8)
                    .write(to: tmp.appendingPathComponent("export-day.csv"))
                try? Data(ExportService.jsonText(sessions: all, scope: .all).utf8)
                    .write(to: tmp.appendingPathComponent("export-all.json"))
                print("dumpExport: wrote \(daySessions.count) day / \(all.count) all")
            }
        }
        // `-demoCountdown` starts a 20s countdown so the auto-end path can be
        // exercised without typing into the simulator.
        if CommandLine.arguments.contains("-demoCountdown") {
            SessionStore.shared.start(title: "测试倒计时", plannedDuration: 20)
        }
        // `-demoStopwatch` starts a mode-2 session so its 20-minute reminder grid
        // can be inspected.
        if CommandLine.arguments.contains("-demoStopwatch") {
            SessionStore.shared.start(title: "写作", plannedDuration: nil)
        }
        // `-demoTrickyTitle` inserts a record whose title needs CSV quoting.
        if CommandLine.arguments.contains("-demoTrickyTitle"),
           !UserDefaults.standard.bool(forKey: "didSeedTrickyTitle") {
            UserDefaults.standard.set(true, forKey: "didSeedTrickyTitle")
            SessionStore.shared.insertDebugSession(
                title: "写作, \"深度\" 工作",
                startedAt: Date().addingTimeInterval(-2 * 3600),
                endedAt: Date().addingTimeInterval(-70 * 60)
            )
        }
        // `-demoParse` dumps how the one-phrase parser reads sample utterances.
        if CommandLine.arguments.contains("-demoParse") {
            let samples = [
                "做饭25分钟", "做饭 25 分钟", "看书半小时", "写作",
                "健身1小时20分钟", "跑步 40", "25分钟做饭", "练习8段锦"
            ]
            let lines = samples.map { sample -> String in
                let parsed = QuickInputParser.parse(sample)
                let seconds = parsed.seconds.map { String(Int($0)) } ?? "nil"
                return "\(sample)  →  title=[\(parsed.title)]  seconds=\(seconds)"
            }.joined(separator: "\n")
            try? lines.write(
                to: URL.temporaryDirectory.appendingPathComponent("parse.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        // `-demoQuick` runs the Siri intent with a spoken-style phrase.
        if CommandLine.arguments.contains("-demoQuick") {
            Task {
                var intent = QuickStartSessionIntent()
                intent.content = "做饭25分钟"
                _ = try? await intent.perform()
            }
        }
        if CommandLine.arguments.contains("-demoIntent") {
            Task {
                var intent = StartSessionIntent()
                intent.title = "快捷指令测试"
                intent.minutes = 25
                let result = try? await intent.perform()
                print("demoIntent result: \(String(describing: result))")
            }
        }
        if CommandLine.arguments.contains("-stopActive") {
            SessionStore.shared.stopActive()
        }
        if CommandLine.arguments.contains("-demoYesterday") {
            SessionStore.shared.selectDay(Date().addingTimeInterval(-86_400))
        }
        // `-dumpLiveActivity` writes what the system actually holds, twice.
        if CommandLine.arguments.contains("-dumpLiveActivity") {
            for delay in [2.0, 8.0, 26.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Task {
                        let report = await SessionStore.shared.liveActivityDebugReport()
                        try? ("[+\(Int(delay))s]\n" + report).write(
                            to: URL.temporaryDirectory.appendingPathComponent("liveactivity.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                        print("LiveActivity dump:\n\(report)")
                    }
                }
            }
        }
        // `-dumpPending` writes the planned reminder schedule to the sandbox
        // twice (right away, and after a countdown would have finished).
        if CommandLine.arguments.contains("-dumpPending") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Task {
                    await SessionReminderScheduler.shared.dumpForDebug(
                        session: SessionStore.shared.active
                    )
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 26) {
                Task {
                    await SessionReminderScheduler.shared.dumpForDebug(
                        session: SessionStore.shared.active
                    )
                }
            }
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(Persistence.shared)
        }
    }
}
