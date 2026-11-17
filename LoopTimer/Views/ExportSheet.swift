//
//  ExportSheet.swift
//  LoopTimer
//
//  Export picker: the day currently on screen, or everything ever recorded.
//  Each row *is* the share action (ShareLink), so no imperative share sheet.
//

import SwiftUI

struct ExportSheet: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var dayFiles: [ExportFile] = []
    @State private var allFiles: [ExportFile] = []

    var body: some View {
        NavigationStack {
            List {
                section(
                    title: "当天 · \(store.day.dayTitleText())",
                    files: dayFiles,
                    empty: "这一天还没有记录"
                )

                section(
                    title: "全部记录",
                    files: allFiles,
                    empty: "还没有任何记录"
                )

                Section {
                    Text("CSV 使用逗号分隔、带 UTF-8 BOM，可直接用 Excel / Numbers 打开；JSON 里的时间戳是带时区偏移的 ISO-8601。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { build() }
        }
    }

    private func section(title: String, files: [ExportFile], empty: String) -> some View {
        Section(title) {
            if files.isEmpty {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(files) { file in
                    ShareLink(item: file.url) {
                        HStack {
                            Image(systemName: file.title == "JSON" ? "curlybraces" : "tablecells")
                                .foregroundStyle(.blue)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.title)
                                    .font(.subheadline.weight(.medium))
                                Text(file.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func build() {
        let daySessions = store.sessions
        let allSessions = store.allSessions()

        dayFiles = [
            ExportService.makeJSON(sessions: daySessions, scope: .day(store.day)),
            ExportService.makeCSV(sessions: daySessions, scope: .day(store.day))
        ].compactMap { $0 }

        allFiles = [
            ExportService.makeJSON(sessions: allSessions, scope: .all),
            ExportService.makeCSV(sessions: allSessions, scope: .all)
        ].compactMap { $0 }
    }
}
