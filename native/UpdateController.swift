import AppKit
import Combine
import Sparkle

/// Sparkle owns archive signature validation, downloading, installation, and relaunch.
final class UpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    let policy: ManagedPolicy
    private var observations: [NSKeyValueObservation] = []

    /// DisableUpdates never starts the updater, so Sparkle makes no checks at all.
    /// AutomaticUpdateChecks is reapplied on every launch, overriding the user's choice.
    init(policy: ManagedPolicy = .current) {
        self.policy = policy
        controller = SPUStandardUpdaterController(startingUpdater: !policy.disableUpdates, updaterDelegate: nil, userDriverDelegate: nil)
        if !policy.disableUpdates, let forced = policy.automaticUpdateChecks {
            controller.updater.automaticallyChecksForUpdates = forced
        }
        observations.append(controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        })
        observations.append(controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.automaticChecks = updater.automaticallyChecksForUpdates }
        })
    }

    func checkForUpdates() {
        guard !policy.disableUpdates, controller.updater.canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ value: Bool) {
        guard !policy.disableUpdates, policy.automaticUpdateChecks == nil else { return }
        controller.updater.automaticallyChecksForUpdates = value
    }
}
