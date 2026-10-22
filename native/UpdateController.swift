import AppKit
import Combine
import Sparkle

/// Sparkle owns archive signature validation, downloading, installation, and relaunch.
final class UpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    private var observations: [NSKeyValueObservation] = []

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observations.append(controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        })
        observations.append(controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.automaticChecks = updater.automaticallyChecksForUpdates }
        })
    }

    func checkForUpdates() {
        guard controller.updater.canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
}
