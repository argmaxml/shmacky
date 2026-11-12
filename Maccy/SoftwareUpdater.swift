import Sparkle

@Observable
class SoftwareUpdater {
  // This private fork must not install upstream Maccy releases over itself.
  static var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

  var automaticallyChecksForUpdates = false {
    didSet {
      if Self.isAvailable { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
  }

  private var updater: SPUUpdater
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: SoftwareUpdater.isAvailable,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  init() {
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] _, change in
      guard change.newValue != change.oldValue, let newValue = change.newValue else {
        return
      }

      MainActor.assumeIsolated {
        self.automaticallyChecksForUpdates = newValue
      }
    }
  }

  func checkForUpdates() {
    guard Self.isAvailable else { return }
    updater.checkForUpdates()
  }
}
