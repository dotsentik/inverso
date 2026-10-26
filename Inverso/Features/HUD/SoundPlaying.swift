import AppKit

/// Plays the sound that confirms a conversion; separate from the visual feedback, which is a different setting.
@MainActor
protocol SoundPlaying {
    func playConversionSound()
}

/// Plays the bundled conversion sound.
@MainActor
struct SystemSoundPlayer: SoundPlaying {
    static let defaultSoundName = NSSound.Name("word-change")

    private let play: @MainActor () -> Void

    init(
        soundName: NSSound.Name = SystemSoundPlayer.defaultSoundName,
        play: (@MainActor () -> Void)? = nil
    ) {
        self.play =
            play ?? {
                guard let sound = NSSound(named: soundName) else {
                    Log.app.error("Conversion sound \(soundName, privacy: .public) is missing from the bundle")
                    return
                }
                sound.play()
            }
    }

    func playConversionSound() {
        play()
    }
}
