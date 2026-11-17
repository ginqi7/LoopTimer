//
//  SettingsView.swift
//  LoopTimer
//
//  Settings: chime sound + mute.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("selectedChimeSound") private var selectedSound: String = "Bell"
    @AppStorage("isMuted") private var isMuted: Bool = false

    private var selectedSoundName: String {
        ChimeSound.allSounds.first { $0.id == selectedSound }?.name ?? "Bell"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("声音") {
                    NavigationLink(destination: SoundPickerView()) {
                        HStack {
                            Text("提示音")
                            Spacer()
                            Text(selectedSoundName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isMuted)

                    Toggle("静音", isOn: $isMuted)
                }

                Section {
                    Text("静音后，App 内的提示音不再播放，通知也不再发声。记录本身不受影响。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
