import AppKit

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 1 FFI smoke test: call a stub function to verify linker resolves the symbol.
        // manzo_play returns 0 (stub) — we just verify it links and calls without crashing.
        let result = manzo_play(nil)
        precondition(result == 0, "manzo_play stub must return 0")
        NSLog("MANZO Phase 1: FFI smoke test passed — manzo_play returned \(result)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
