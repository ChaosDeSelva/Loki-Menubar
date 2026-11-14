import AppKit
import SwiftUI
import WebKit

enum LokiStyle {
    static let background = Color.black, surface = Color.gray, muted = Color.secondary
}

@main struct AddOnWebTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var passed = 0
        func check(_ name: String, _ value: Bool) {
            guard value else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loki-web-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Add-ons")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let example = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("addons/examples/text-workbench")
        try FileManager.default.copyItem(at: example, to: folder.appendingPathComponent("workbench"))
        let manager = AddOnManager(folder: folder, watch: false)
        while manager.scanning { try await Task.sleep(nanoseconds: 10_000_000) }
        let package = manager.packages[0]
        check("Custom interface explicitly enabled", manager.setEnabled(true, package: package))
        let session = AddOnSession(manager: manager)
        let command = package.manifest.commands.first { $0.type == .view }!
        session.open(package: package, command: command)
        let host = NSHostingView(rootView: AddOnWebView(package: package, command: command, session: session))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 680, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close(); session.clear() }
        func findWeb(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap(findWeb).first
        }
        var web: WKWebView?
        let readyDeadline = Date().addingTimeInterval(20)
        while web == nil && Date() < readyDeadline {
            host.layoutSubtreeIfNeeded(); web = findWeb(host)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let web else { throw LauncherFailure("Web view did not mount") }
        func js(_ source: String) async throws -> Any? {
            try await withCheckedThrowingContinuation { continuation in
                var completed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard !completed else { return }; completed = true
                    continuation.resume(throwing: LauncherFailure("WebKit evaluation timed out"))
                }
                web.evaluateJavaScript(source) { result, error in
                    guard !completed else { return }; completed = true
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result) }
                }
            }
        }
        var ready = false
        while !ready && Date() < readyDeadline {
            ready = (try? await js("document.title === 'Text Workbench' && typeof window.loki === 'object' && document.readyState === 'complete'")) as? Bool == true
            if !ready { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        check("Bundled HTML loads with the native bridge", ready)
        _ = try await js("document.querySelector('#source').value='Hello from WebKit'; document.querySelector('#run').click();")
        let resultDeadline = Date().addingTimeInterval(10)
        var text = ""
        while text.isEmpty && Date() < resultDeadline {
            text = (try await js("document.querySelector('#result').value")) as? String ?? ""
            if text.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        check("Custom UI calls a declared script and receives its result", text == "HELLO FROM WEBKIT")
        _ = try await js("window.testError=''; window.loki.run('missing',{}).catch(e=>window.testError=e.message); void 0;")
        try await Task.sleep(nanoseconds: 200_000_000)
        check("Unknown bridge commands reject their promise", (try await js("window.testError")) as? String == "Command unavailable or another command is running.")
        _ = try await js("window.testError=''; window.loki.run('transform',{text:42}).catch(e=>window.testError=e.message); void 0;")
        try await Task.sleep(nanoseconds: 200_000_000)
        check("Invalid input types reject their promise", ((try await js("window.testError")) as? String)?.contains("string input") == true)
        let previousURL = web.url
        _ = try await js("location.href='https://example.com/loki-test-no-navigation';")
        try await Task.sleep(nanoseconds: 200_000_000)
        check("Remote navigation stays inside the local interface", web.url == previousURL)
        manager.setEnabled(false, package: package)
        _ = try await js("window.testError=''; window.loki.run('transform',{text:'blocked',mode:'UPPERCASE'}).catch(e=>window.testError=e.message); void 0;")
        try await Task.sleep(nanoseconds: 200_000_000)
        check("Disabling revokes native execution from a loaded page", !session.running && session.command == nil && session.error != nil)
        print("\(passed) WebKit integration checks passed")
    }
}
