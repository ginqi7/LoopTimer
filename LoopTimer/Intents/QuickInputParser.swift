//
//  QuickInputParser.swift
//  LoopTimer
//
//  Turns one spoken phrase into a task name + duration.
//
//  Siri can only capture a single free-text parameter per App Shortcut, so the
//  whole utterance arrives as one string and is parsed here:
//
//      "做饭25分钟"      → 做饭    / 25 min
//      "看书 半小时"      → 看书    / 30 min
//      "健身1小时20分钟"   → 健身    / 80 min
//      "跑步 40"          → 跑步    / 40 min   (trailing bare number = minutes)
//      "写作"             → 写作    / nil      (不定时)
//

import Foundation

enum QuickInputParser {

    struct Parsed {
        let title: String
        /// nil → 不定时 (mode 2).
        let seconds: TimeInterval?
    }

    /// Phrases that mean a fixed duration without a number.
    private static let fixedMinutes: [(String, Double)] = [
        ("一个半小时", 90),
        ("半个小时", 30),
        ("半小时", 30),
        ("一刻钟", 15)
    ]

    private static let unitPatterns: [(pattern: String, unit: Double)] = [
        ("(\\d+(?:\\.\\d+)?)\\s*(?:个)?\\s*(?:小时|钟头|hours?|hrs?|h)", 3600),
        ("(\\d+)\\s*(?:分钟|分|min(?:ute)?s?|m)", 60)
    ]

    static func parse(_ raw: String) -> Parsed {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Parsed(title: "", seconds: nil) }

        for (phrase, minutes) in fixedMinutes where text.contains(phrase) {
            text = text.replacingOccurrences(of: phrase, with: " ")
            return Parsed(title: cleaned(text), seconds: minutes * 60)
        }

        // Sum every duration component ("1小时20分钟" = 80 分钟) and strip them all,
        // so nothing is left behind in the task name.
        var seconds: Double = 0
        var matched: [Range<String.Index>] = []

        for rule in unitPatterns {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                continue
            }
            let full = NSRange(text.startIndex..., in: text)
            for result in regex.matches(in: text, range: full) {
                guard let valueRange = Range(result.range(at: 1), in: text),
                      let value = Double(text[valueRange]),
                      value > 0,
                      let totalRange = Range(result.range, in: text) else { continue }
                seconds += value * rule.unit
                matched.append(totalRange)
            }
        }

        if seconds > 0, !matched.isEmpty {
            for range in matched.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                text.removeSubrange(range)
            }
            return Parsed(title: cleaned(text), seconds: seconds)
        }

        // "跑步 40" — a trailing bare number is read as minutes.
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*$"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let valueRange = Range(match.range(at: 1), in: text),
           let value = Double(text[valueRange]),
           let totalRange = Range(match.range, in: text),
           value > 0 {
            text.removeSubrange(totalRange)
            return Parsed(title: cleaned(text), seconds: value * 60)
        }

        return Parsed(title: cleaned(text), seconds: nil)
    }

    /// Collapses the whitespace left behind by removing the duration.
    private static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
