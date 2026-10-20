import Sparkle

/// The part of SPUUpdater the settings use. Lets tests substitute a fake.
@MainActor
protocol UpdaterSettings: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
}

extension SPUUpdater: UpdaterSettings {}
