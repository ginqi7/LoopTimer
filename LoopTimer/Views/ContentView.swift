//
//  ContentView.swift
//  LoopTimer
//
//  App container. Root is now the day recorder; the legacy loop-timer screen
//  (TimerView) is retained in the repo only until milestone ⑤ retires it.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TodayView()
            .persistentSystemOverlays(.hidden)
            .onAppear {
                // Lock to portrait orientation
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                AppDelegate.orientationLock = .portrait
            }
    }
}

#Preview {
    ContentView()
}
