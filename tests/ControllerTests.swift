import AppKit

/// Drives VisibilityController's macOS 27 bookkeeping through a fake allowlist.
/// Each scenario mirrors a defect found in review or on hardware; none touches the real menu bar.
final class FakeAllowlist: MenuBarAllowlist {
    var requests: [(items: Set<String>, reply: (String?) -> Void)] = []
    var reveals = 0
    var replyImmediately: String??
    func hide(_ items: Set<String>, completion: @escaping (String?) -> Void) {
        if let reply = replyImmediately { completion(reply); return }
        requests.append((items, completion))
    }
    func reveal() { reveals += 1 }
}

@main
enum ControllerTests {
    static var passed = 0
    static func check(_ name: String, _ condition: Bool) {
        guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1; print("PASS: \(name)")
    }
    static func drain(_ seconds: TimeInterval = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    static let ollama = "menu-slot:com.electron.ollama:0"

    @MainActor
    static func make(capture: @escaping () -> Bool = { false }, installed: Bool = true,
                     timeout: TimeInterval = 5) -> (VisibilityController, FakeAllowlist) {
        let fake = FakeAllowlist()
        let controller = VisibilityController(backend: .allowlist, allowlist: fake, captureInUse: capture,
                                              installed: { installed }, confirmationTimeout: timeout)
        controller.settings(delay: 30, autoRehide: false, hoverReveal: false)
        return (controller, fake)
    }

    static func main() {
        MainActor.assumeIsolated { run() }
        print("\(passed) controller checks passed")
    }

    @MainActor
    static func run() {
        do {
            var capturing = true
            let (c, fake) = make(capture: { capturing })
            c.apply([ollama])
            check("Capture already active prevents the initial hide", fake.requests.isEmpty && c.privacyHold && c.paused)
            capturing = false; c.checkCapture()
            check("Initial capture hold resumes after capture ends", fake.requests.count == 1)
            capturing = true; fake.requests[0].reply(nil)
            check("Capture starting before confirmation cancels the pending hide", c.mode == .revealed && c.privacyHold && !c.allowlistPending && fake.reveals == 1)
            capturing = false; c.checkCapture(); fake.requests[1].reply(nil)
            capturing = true; c.refreshAllowlist()
            check("Refresh cannot hide recording indicators", fake.requests.count == 2 && c.privacyHold && c.mode == .revealed)
            c.restoreForQuit()
        }
        do {
            var moves: [Set<String>] = []
            var completions: [CheckedContinuation<MenuBarArranger.Outcome, Never>] = []
            let c = VisibilityController(backend: .divider, allowlist: FakeAllowlist(), trusted: { true }, arrange: { hidden, _, _ in
                moves.append(hidden)
                return await withCheckedContinuation { completions.append($0) }
            })
            c.settings(delay: 30, autoRehide: false, hoverReveal: false)
            c.apply([ollama]); drain(0.4)
            c.apply(["menu-slot:com.apple.Safari:0"]); c.apply([]); c.revealAll()
            completions[0].resume(returning: MenuBarArranger.Outcome()); drain(0.4)
            check("Realm changes during a move coalesce to the latest selection", moves.count == 2 && moves[1].isEmpty && c.hidden.isEmpty)
            completions[1].resume(returning: MenuBarArranger.Outcome()); drain()
            check("Clearing a queued selection finishes with all icons visible", c.mode == .idle)
            c.apply([ollama]); drain(0.4)
            c.apply(["menu-slot:com.apple.Safari:0"]); c.revealAll()
            completions[2].resume(returning: MenuBarArranger.Outcome()); drain(0.4)
            completions[3].resume(returning: MenuBarArranger.Outcome()); drain()
            check("Reveal All survives a queued realm change", c.mode == .revealed && c.paused)
            c.apply([ollama]); drain(0.4); c.restoreForQuit()
            completions[4].resume(returning: MenuBarArranger.Outcome()); drain()
            c.apply([])
            check("Quit prevents late arrangement results and new work", moves.count == 5 && c.mode == .arranging)
        }
        do {
            let (c, fake) = make()
            c.apply([ollama])
            check("Apply requests one hide and waits for macOS", fake.requests.count == 1 && c.mode == .revealed && c.allowlistPending)
            check("Only hideable choices reach the allowlist", fake.requests[0].items == [ollama])
            fake.requests[0].reply(nil)
            check("Confirmed hide collapses", c.mode == .collapsed && !c.allowlistPending)
            c.reveal()
            check("Reveal drops the allowlist", c.mode == .revealed && fake.reveals == 1)
            c.collapse()
            check("Collapse after reveal requests a fresh hide", fake.requests.count == 2)
        }
        do {
            let (c, fake) = make()
            c.apply([ollama, "menu:system:clock", "menu-slot:io.github.ChaosDeSelva.Loki:0"])
            check("System and Loki IDs are filtered from the hidden set", c.hidden == [ollama])
            fake.requests[0].reply(nil)
            c.reveal()
            let stale = fake.requests[0].reply
            stale(nil)
            check("A stale confirmation cannot hide after reveal", c.mode == .revealed)
        }
        do {
            let (c, fake) = make()
            c.apply([ollama])
            c.collapse(); c.collapse(); c.toggle()
            check("Repeated collapse while pending never re-requests (no self-cancelling)", fake.requests.count == 1)
            fake.requests[0].reply(nil)
            check("The single request still confirms", c.mode == .collapsed)
        }
        do {
            let (c, fake) = make()
            c.apply([ollama])
            c.revealAll()
            check("Reveal All during a pending hide cancels it", c.mode == .revealed && !c.allowlistPending && fake.reveals >= 1 && c.paused)
            fake.requests[0].reply(nil)
            check("The cancelled hide's late confirmation is ignored", c.mode == .revealed)
            c.collapse()
            check("Hiding works again after Reveal All", fake.requests.count == 2)
            fake.requests[1].reply(nil)
            check("And confirms normally", c.mode == .collapsed && !c.paused)
        }
        do {
            let (c, fake) = make()
            c.apply([ollama])
            c.apply([])
            check("Clearing the choice during a pending hide goes idle and drops the allowlist", c.mode == .idle && !c.allowlistPending && fake.reveals >= 1)
            fake.requests[0].reply(nil)
            check("The abandoned hide cannot reactivate", c.mode == .idle)
        }
        do {
            let (c, fake) = make()
            fake.replyImmediately = .some("macOS said no")
            c.apply([ollama])
            check("A synchronous error is reported and pauses", c.failure == "macOS said no" && c.paused && c.mode == .revealed)
            drain(0.1)
            check("The confirmation timeout does not overwrite the real error", c.failure == "macOS said no")
        }
        do {
            let (c, fake) = make(timeout: 0.05)
            c.apply([ollama])
            drain(0.2)
            check("An unconfirmed hide times out to everything visible", c.mode == .revealed && !c.allowlistPending && fake.reveals >= 1 && c.paused
                  && c.failure == "macOS did not confirm hiding. Every icon is visible.")
        }
        do {
            let (c, fake) = make()
            c.apply([ollama]); fake.requests[0].reply(nil)
            c.refreshAllowlist()
            check("Refresh while hidden re-issues the hide and stays collapsed", fake.requests.count == 2 && c.mode == .collapsed)
            fake.requests[1].reply(nil)
            check("A confirmed refresh keeps icons hidden", c.mode == .collapsed && !c.allowlistPending)
            c.refreshAllowlist()
            fake.requests[2].reply("refresh failed")
            check("A failed refresh shows everything with the error", c.mode == .revealed && c.failure == "refresh failed")
            c.refreshAllowlist()
            check("Refresh does nothing while revealed", fake.requests.count == 3)
        }
        do {
            let (c, fake) = make(installed: false)
            c.apply([ollama])
            check("Outside Applications, hiding is refused with an explanation", fake.requests.isEmpty && c.paused && c.failure?.contains("Applications") == true)
        }
        do {
            var capturing = false
            let (c, fake) = make(capture: { capturing })
            c.apply([ollama]); fake.requests[0].reply(nil)
            capturing = true; c.checkCapture()
            check("Microphone or camera use shows every icon", c.mode == .revealed && c.privacyHold && fake.reveals == 1)
            c.collapse()
            check("Hiding stays off while capture continues", fake.requests.count == 1)
            capturing = false; c.checkCapture()
            check("Hiding resumes when capture ends", !c.privacyHold && fake.requests.count == 2)
            fake.requests[1].reply(nil)
            capturing = true; c.checkCapture()
            c.revealAll()
            capturing = false; c.checkCapture()
            check("Reveal All during capture is respected afterwards", c.mode == .revealed && fake.requests.count == 2)
        }
        do {
            let c = VisibilityController(backend: .unavailable, allowlist: FakeAllowlist(), captureInUse: { false }, installed: { true })
            c.apply([ollama])
            check("Unavailable backend explains and stays visible", c.mode == .idle && c.failure?.contains("does not expose") == true)
        }
        do {
            let (c, fake) = make()
            c.revealAll()
            c.toggle()
            check("Toggle with nothing chosen does nothing", fake.requests.isEmpty && c.mode == .idle)
            c.apply([ollama]); fake.requests[0].reply(nil)
            c.toggle()
            check("Toggle reveals when hidden", c.mode == .revealed)
            c.toggle()
            check("Toggle hides when revealed", fake.requests.count == 2)
            c.restoreForQuit()
            check("Quit drops the allowlist", !c.allowlistPending && fake.reveals >= 2)
        }
    }
}
