//
//  ExportService.swift
//  LoopTimer
//
//  Turns records into JSON and CSV files.
//
//  Format decisions worth knowing:
//   • JSON carries an explicit version + time zone and ISO-8601 timestamps with
//     the local offset, so a file stays interpretable on another machine.
//   • CSV uses "yyyy-MM-dd HH:mm:ss" (local) because that is what spreadsheet
//     apps parse as a date, and is written with a UTF-8 BOM, otherwise Excel on
//     Windows renders Chinese titles as mojibake.
//   • CSV is RFC 4180: fields containing , " or newlines are quoted, quotes are
//     doubled, CRLF line endings.
//

import Foundation

struct ExportFile: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let url: URL
}

enum ExportScope {
    case day(Date)
    case all

    var key: String {
        switch self {
        case .day: return "day"
        case .all: return "all"
        }
    }
}

@MainActor
enum ExportService {

    // MARK: - Files

    static func makeJSON(sessions: [Session], scope: ExportScope, now: Date = .now) -> ExportFile? {
        guard !sessions.isEmpty else { return nil }
        let text = jsonText(sessions: sessions, scope: scope, now: now)
        guard let url = write(text, fileName: fileName(scope: scope, ext: "json", now: now)) else { return nil }
        return ExportFile(
            title: "JSON",
            subtitle: "\(sessions.count) 条 · \(byteText(url))",
            url: url
        )
    }

    static func makeCSV(sessions: [Session], scope: ExportScope, now: Date = .now) -> ExportFile? {
        guard !sessions.isEmpty else { return nil }
        let text = csvText(sessions: sessions, now: now)
        guard let url = write(text, fileName: fileName(scope: scope, ext: "csv", now: now)) else { return nil }
        return ExportFile(
            title: "CSV",
            subtitle: "\(sessions.count) 条 · \(byteText(url))",
            url: url
        )
    }

    // MARK: - JSON

    private struct JSONExport: Encodable {
        let app: String
        let version: Int
        let exportedAt: String
        let scope: String
        let day: String?
        let timeZone: String
        let sessionCount: Int
        let totalRecordedSeconds: Int
        let sessions: [JSONSession]
    }

    private struct JSONSession: Encodable {
        let id: String
        let title: String
        let mode: String
        let plannedDurationSeconds: Int?
        let reminderIntervalSeconds: Int?
        let start: String
        let end: String?
        let durationSeconds: Int
        let endReason: String
    }

    static func jsonText(sessions: [Session], scope: ExportScope, now: Date = .now) -> String {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        let payload = JSONExport(
            app: "LoopTimer",
            version: 1,
            exportedAt: isoText(now),
            scope: scope.key,
            day: {
                if case .day(let date) = scope { return dayKey(date) }
                return nil
            }(),
            timeZone: TimeZone.current.identifier,
            sessionCount: ordered.count,
            totalRecordedSeconds: Int(ordered.reduce(0) { $0 + $1.duration(asOf: now) }.rounded()),
            sessions: ordered.map { session in
                JSONSession(
                    id: session.id.uuidString,
                    title: session.title,
                    mode: session.mode == .countdown ? "countdown" : "stopwatch",
                    plannedDurationSeconds: session.plannedDuration.map { Int($0.rounded()) },
                    reminderIntervalSeconds: session.reminderInterval.map { Int($0.rounded()) },
                    start: isoText(session.startedAt),
                    end: session.endedAt.map(isoText),
                    durationSeconds: Int(session.duration(asOf: now).rounded()),
                    endReason: session.endReason?.rawValue ?? "active"
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    // MARK: - CSV

    static let csvHeader = [
        "title",
        "start",
        "end",
        "duration_seconds",
        "mode",
        "reminder_interval_seconds",
        "end_reason"
    ]

    static func csvText(sessions: [Session], now: Date = .now) -> String {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        var lines = [csvHeader.joined(separator: ",")]

        for session in ordered {
            let fields = [
                session.title,
                localText(session.startedAt),
                session.endedAt.map(localText) ?? "",
                String(Int(session.duration(asOf: now).rounded())),
                session.mode == .countdown ? "countdown" : "stopwatch",
                session.reminderInterval.map { String(Int($0.rounded())) } ?? "",
                session.endReason?.rawValue ?? "active"
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        // BOM so Excel recognises UTF-8; CRLF per RFC 4180.
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 quoting.
    static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Helpers

    private static func fileName(scope: ExportScope, ext: String, now: Date) -> String {
        switch scope {
        case .day(let date):
            return "LoopTimer-\(dayKey(date)).\(ext)"
        case .all:
            return "LoopTimer-all-\(dayKey(now)).\(ext)"
        }
    }

    private static func write(_ text: String, fileName: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        do {
            // Raw bytes so the BOM (and any future change) survives unmodified.
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            print("ExportService: write failed — \(error)")
            return nil
        }
    }

    private static func byteText(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// ISO-8601 with the local offset ("2026-11-16T18:57:00+08:00").
    private static func isoText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// "2026-11-16 18:57:00" — the shape spreadsheets parse as a date.
    private static func localText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
