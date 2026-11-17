//
//  AudioService.swift
//  LoopTimer
//
//  In-app chime playback.
//
//  The audio session is activated only while a chime is playing and released
//  afterwards. It is deliberately *not* held open: the app has no
//  `UIBackgroundModes: audio` any more, because nothing depends on the process
//  staying alive (durations come from timestamps, reminders come from the system).
//

import AVFoundation
import AudioToolbox
import Foundation

final class AudioService {

    private var player: AVAudioPlayer?
    private var releaseWorkItem: DispatchWorkItem?

    // MARK: - Public

    func playChime(soundName: String = "Bell", isMuted: Bool = false) {
        guard !isMuted else { return }

        guard let sound = ChimeSound.allSounds.first(where: { $0.id == soundName }),
              let soundURL = sound.bundleURL else {
            AudioServicesPlaySystemSound(1013)
            return
        }

        do {
            try activateSession()
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.volume = 1.0
            player.play()
            self.player = player
            scheduleRelease(after: player.duration)
        } catch {
            print("AudioService: playback failed — \(error)")
            AudioServicesPlaySystemSound(1013)
        }
    }

    // MARK: - Session

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        releaseWorkItem?.cancel()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
    }

    private func scheduleRelease(after duration: TimeInterval) {
        releaseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.player?.stop()
            self?.player = nil
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: [.notifyOthersOnDeactivation])
        }
        releaseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, duration + 0.2), execute: item)
    }
}
