//
//  Duration+Formatting.swift
//  LoopTimer
//
//  Chinese duration/clock formatting. Kept manual (no locale lookup) so the
//  notification text and the in-app text always agree, whatever the device locale.
//

import Foundation

extension TimeInterval {
    /// "1 小时 20 分钟" / "25 分钟" / "42 秒" / "0 秒"
    func durationText() -> String {
        let total = Int(self.rounded())
        guard total > 0 else { return "0 秒" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes) 分 \(seconds) 秒" : "\(minutes) 分钟"
        }
        return "\(seconds) 秒"
    }

    /// Compact "1 小时 20 分" — for tight labels where 秒钟 noise is unwanted.
    func durationTextCompact() -> String {
        let total = Int(self.rounded())
        guard total > 0 else { return "0 分" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        if minutes > 0 {
            return "\(minutes) 分"
        }
        return "\(total) 秒"
    }

    /// "1:20:35" once past an hour, otherwise "20:35".
    func clockText() -> String {
        let total = Int(max(0, self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Date {
    /// "10:24" in the current time zone.
    func timeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// "11月16日 周日"
    func dayTitleText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: self)
    }

    var nextMidnight: Date {
        let start = Calendar.current.startOfDay(for: self)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
    }
}
