//
//  TodayView.swift
//  LoopTimer
//
//  Container: two horizontally-paged screens.
//
//    计时 (TimerPageView)  ←→  今天 (DayPageView)
//
//  Swipe to switch; the two dots are a tappable affordance so the gesture is
//  discoverable. Toolbar contents follow the current page: the date and day
//  navigation only make sense on the day page, settings only on the timer page.
//

import SwiftUI

struct TodayView: View {
    @StateObject private var store = SessionStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var page: Page = .timer
    @State private var audioService = AudioService()
    @State private var showingExport = false
    @State private var showingSettings = false
    @AppStorage("selectedChimeSound") private var selectedChimeSound: String = "Bell"
    @AppStorage("isMuted") private var isMuted: Bool = false

    private let calendar = Calendar.current

    private enum Page: Int, Hashable {
        case timer
        case day
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pageDots
                    .padding(.top, 2)

                TabView(selection: $page) {
                    TimerPageView(store: store)
                        .tag(Page.timer)

                    DayPageView(store: store) { showingExport = true }
                        .tag(Page.day)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if page == .day {
                        Button {
                            store.selectDay(calendar.date(byAdding: .day, value: -1, to: store.day) ?? store.day)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                        }
                        .accessibilityLabel("前一天")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(page == .timer ? "计时" : store.day.dayTitleText())
                        .font(.subheadline.weight(.medium))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if page == .day {
                        if calendar.isDateInToday(store.day) {
                            Button {
                                store.selectDay(calendar.date(byAdding: .day, value: 1, to: store.day) ?? store.day)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .accessibilityLabel("后一天")
                        } else {
                            Button("今天") { store.goToToday() }
                                .font(.footnote.weight(.semibold))
                        }
                    } else {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash" : "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("设置")
                    }
                }
            }
            .onAppear {
                store.onAutoComplete = { _ in
                    audioService.playChime(soundName: selectedChimeSound, isMuted: isMuted)
                }
                store.onReminderDue = { _, _ in
                    // In-app banners are suppressed, so the chime is played here.
                    audioService.playChime(soundName: selectedChimeSound, isMuted: isMuted)
                }
                store.reconcile()
#if DEBUG
                if CommandLine.arguments.contains("-showDay") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { page = .day }
                }
                if CommandLine.arguments.contains("-showExport") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showingExport = true }
                }
                if CommandLine.arguments.contains("-showSettings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showingSettings = true }
                }
#endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.reconcile()
                    // Activity.request only succeeds while active.
                    store.syncLiveActivity()
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportSheet(store: store)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    /// Two dots: current page + tap-to-switch, so the swipe is discoverable.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach([Page.timer, Page.day], id: \.self) { candidate in
                Circle()
                    .fill(page == candidate ? Color.primary.opacity(0.65) : Color.secondary.opacity(0.22))
                    .frame(width: 6, height: 6)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { page = candidate }
                    }
            }
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(page == .timer ? "当前：计时页" : "当前：今天页")
    }
}

#Preview {
    TodayView()
}
