//
//  SessionIntents.swift
//  LoopTimer
//
//  Shortcuts / Siri / Spotlight entry points.
//
//  开始记录  — takes 任务 + 时长（分钟）; 0 means "no duration" → stopwatch mode.
//  停止记录  — closes the running session.
//
//  They run in the app's own process (no extension needed), so they can talk to
//  SessionStore directly. `perform()` awaits the reminder registration, because a
//  background-run intent is suspended as soon as it returns.
//

import AppIntents
import Foundation

// MARK: - Start

struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "开始记录"
    static var description = IntentDescription("记录一件事：给定时长则倒计时，时长填 0 则不定时记录（每 20 分钟提醒一次）。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "任务", requestValueDialog: "要记录什么？")
    var title: String

    @Parameter(title: "时长（分钟）", description: "0 表示不定时", default: 0)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("记录 \(\.$title)，时长 \(\.$minutes) 分钟")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionIntentError.emptyTitle
        }

        SessionStore.shared.attachIfNeeded()
        let planned: TimeInterval? = minutes > 0 ? TimeInterval(minutes * 60) : nil

        guard let session = await SessionStore.shared.startAndSchedule(
            title: trimmed,
            plannedDuration: planned
        ) else {
            throw SessionIntentError.couldNotStart
        }

        let suffix = planned.map { "，\($0.durationTextCompact())后提醒" } ?? "，每 20 分钟提醒"
        return .result(dialog: "开始记录「\(session.title)」\(suffix)")
    }
}

// MARK: - Quick (one phrase)

/// Siri path. App Shortcut phrases can only carry a single free-text parameter,
/// so the whole utterance arrives here and is parsed into name + duration.
struct QuickStartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记录（一句话）"
    static var description = IntentDescription(
        "说「做饭 25 分钟」就会创建名为「做饭」的 25 分钟任务；只说名字则不定时记录。"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "内容", requestValueDialog: "要记录什么？比如「做饭 25 分钟」")
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("记录 \(\.$content)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = QuickInputParser.parse(content)
        guard !parsed.title.isEmpty else {
            throw SessionIntentError.emptyTitle
        }

        SessionStore.shared.attachIfNeeded()
        guard let session = await SessionStore.shared.startAndSchedule(
            title: parsed.title,
            plannedDuration: parsed.seconds
        ) else {
            throw SessionIntentError.couldNotStart
        }

        let suffix = parsed.seconds.map { "，\($0.durationTextCompact())后提醒" } ?? "，每 20 分钟提醒"
        return .result(dialog: "开始记录「\(session.title)」\(suffix)")
    }
}

// MARK: - Stop

struct StopSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "停止记录"
    static var description = IntentDescription("结束当前正在记录的任务。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SessionStore.shared.attachIfNeeded()

        guard let active = SessionStore.shared.active else {
            return .result(dialog: "现在没有正在记录的任务")
        }

        let name = active.title
        SessionStore.shared.stopActive()
        return .result(dialog: "已停止「\(name)」")
    }
}

// MARK: - Errors

enum SessionIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyTitle
    case couldNotStart

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle: return "任务名不能为空"
        case .couldNotStart: return "记录没有开始成功"
        }
    }
}

// MARK: - Siri phrases

struct LoopTimerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // 短语里不能塞 String/Int 参数（App Intents 只允许 AppEntity/AppEnum，且一句一个），
        // 所以这里只负责「唤醒」，内容由 Siri 追问一句后交给 QuickInputParser 解析。
        //
        //   「嘿 Siri，用 LoopTimer 计时」→「要记录什么？」→「做饭 25 分钟」
        //
        // 短语必须包含 \(.applicationName)，这是 Apple 的硬性要求。
        AppShortcut(
            intent: QuickStartSessionIntent(),
            phrases: [
                "用 \(.applicationName) 计时",
                "用 \(.applicationName) 速记",
                "用 \(.applicationName) 记录一下"
            ],
            shortTitle: "计时（一句话）",
            systemImageName: "timer"
        )

        AppShortcut(
            intent: StopSessionIntent(),
            phrases: [
                "用 \(.applicationName) 停止记录"
            ],
            shortTitle: "停止记录",
            systemImageName: "stop.circle"
        )
    }
}
