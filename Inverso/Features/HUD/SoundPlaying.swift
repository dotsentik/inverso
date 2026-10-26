import AppKit

/// Plays the sound that confirms a conversion; separate from the visual feedback, which is a different setting.
@MainActor
protocol SoundPlaying {
    func playConversionSound()
}

/// Plays a short system sound effect.
@MainActor
struct SystemSoundPlayer: SoundPlaying {
    static let defaultSoundName = NSSound.Name("Tink")

    private let play: @MainActor () -> Void

    init(
        soundName: NSSound.Name = SystemSoundPlayer.defaultSoundName,
        play: (@MainActor () -> Void)? = nil
    ) {
        self.play = play ?? { NSSound(named: soundName)?.play() }
    }

    func playConversionSound() {
        play()
    }
}
