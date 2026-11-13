import AppKit

/// Plays the sound that confirms a conversion; separate from the visual feedback, which is a different setting.
@MainActor
protocol SoundPlaying {
    func playConversionSound()
}

/// Plays the conversion sound: a standard macOS system sound (/System/Library/Sounds).
@MainActor
struct SystemSoundPlayer: SoundPlaying {
    static let defaultSoundName = NSSound.Name("Tink")

    private let play: @MainActor () -> Void

    init(
        soundName: NSSound.Name = SystemSoundPlayer.defaultSoundName,
        play: (@MainActor () -> Void)? = nil
    ) {
        self.play =
            play ?? {
                guard let sound = NSSound(named: soundName) else {
                    Log.app.error("Conversion sound \(soundName, privacy: .public) is not available")
                    return
                }
                sound.play()
            }
    }

    func playConversionSound() {
        play()
    }
}
