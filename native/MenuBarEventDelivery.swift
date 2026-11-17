import AppKit
import ApplicationServices

// A process-local post alone is ignored for hosted status items. Relay through the
// session stream, then confirm the source app received this operation’s tagged event.
final class MenuBarEventDelivery {
    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
    let event: CGEvent
    let receiver: pid_t
    let token = Int64.random(in: 1...(Int64.max - 1))
    var acknowledged = false
    var forwarded = false
    var started = false

    init(event: CGEvent, receiver: pid_t) {
        self.event = event.copy() ?? event
        self.receiver = receiver
        self.event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(receiver))
        self.event.setIntegerValueField(.eventSourceUserData, value: token)
    }

    @MainActor
    func send() async throws {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let eventMask = CGEventMask(1) << event.type.rawValue
        guard let processTap = CGEvent.tapCreateForPid(pid: receiver, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: eventMask | 1, callback: { _, type, incoming, info in
                guard let info else { return Unmanaged.passUnretained(incoming) }
                let state = Unmanaged<MenuBarEventDelivery>.fromOpaque(info).takeUnretainedValue()
                let tag = incoming.getIntegerValueField(.eventSourceUserData)
                if type == .null, tag == state.token + 1 {
                    if !state.started {
                        state.started = true
                        state.event.post(tap: .cgSessionEventTap)
                    }
                    return nil
                }
                if type == state.event.type, tag == state.token {
                    state.acknowledged = true
                }
                return Unmanaged.passUnretained(incoming)
            }, userInfo: context) else { throw Failure("Cannot create process event tap") }
        defer { CFMachPortInvalidate(processTap) }
        guard let sessionTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .defaultTap, eventsOfInterest: eventMask, callback: { _, type, incoming, info in
                guard let info else { return Unmanaged.passUnretained(incoming) }
                let state = Unmanaged<MenuBarEventDelivery>.fromOpaque(info).takeUnretainedValue()
                if type == state.event.type, incoming.getIntegerValueField(.eventSourceUserData) == state.token, !state.forwarded {
                    state.forwarded = true
                    state.event.postToPid(state.receiver)
                }
                return Unmanaged.passUnretained(incoming)
            }, userInfo: context) else { throw Failure("Cannot create session event tap") }
        defer { CFMachPortInvalidate(sessionTap) }
        let loop = CFRunLoopGetMain()
        var sources: [CFRunLoopSource] = []
        defer { for source in sources { CFRunLoopRemoveSource(loop, source, .commonModes) } }
        for tap in [processTap, sessionTap] {
            guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { throw Failure("Cannot create tap run-loop source") }
            sources.append(source)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard let signal = CGEvent(source: nil) else { throw Failure("Cannot create delivery signal") }
        signal.setIntegerValueField(.eventSourceUserData, value: token + 1)
        signal.postToPid(receiver)
        for _ in 0..<25 {
            if acknowledged { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure("Delivery timed out: started=\(started) session=\(forwarded) ack=\(acknowledged)")
    }

}

@MainActor
final class MenuBarPointerGuard {
    private let original = CGEvent(source: nil)?.location
    private var latestMovement: CGPoint?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hidden = false

    init() {
        // Preserve real movement made during the short relay instead of snapping back over it.
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.mouseMoved.rawValue, callback: { _, type, event, context in
                if type == .mouseMoved, let context {
                    let guardObject = Unmanaged<MenuBarPointerGuard>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { guardObject.latestMovement = event.location }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
    }

    func restore() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let point = latestMovement ?? original { CGWarpMouseCursorPosition(point) }
        if hidden { CGDisplayShowCursor(CGMainDisplayID()); hidden = false }
    }
}
