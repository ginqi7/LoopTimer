//
//  Persistence.swift
//  LoopTimer
//
//  The SwiftData container, reachable from any entry point.
//
//  It lives here rather than inside `LoopTimerApp` because App Intents can be
//  performed while the app is launched in the background for a shortcut, and the
//  store must be able to attach to a context no matter which path got us here.
//

import Foundation
import SwiftData

@MainActor
enum Persistence {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: Session.self)
        } catch {
            // Keep the app usable instead of crashing if the on-disk store is bad.
            print("Persistence: persistent store unavailable, using in-memory — \(error)")
            return try! ModelContainer(
                for: Session.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }()
}
