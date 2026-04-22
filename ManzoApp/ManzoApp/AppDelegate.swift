import AppKit

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep handle alive for the app's lifetime — stored as instance var prevents premature dealloc.
    // Type matches cbindgen output: struct manzo_ManzoHandle * → UnsafeMutablePointer<manzo_ManzoHandle>?
    private var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 2: Open a real MP3 and start playback via the Rust audio pipeline.
        // manzo_open → mpg123 feed/read → cpal float32 CoreAudio output.

        // Locate test MP3: try app bundle first, fall back to dev fixture path
        let mp3Path: String
        if let bundlePath = Bundle.main.path(forResource: "test", ofType: "mp3") {
            mp3Path = bundlePath
        } else {
            // Development fallback — Rust integration test fixture (T-02-11: read-only, not user-controllable)
            mp3Path = "/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/test.mp3"
        }

        guard FileManager.default.fileExists(atPath: mp3Path) else {
            NSLog("MANZO Phase 2: MP3 not found at \(mp3Path) — skipping playback")
            return
        }

        // Open file via FFI — manzo_open returns UnsafeMutablePointer<manzo_ManzoHandle>? (null on failure)
        manzoHandle = manzo_open(mp3Path)
        guard let handle = manzoHandle else {
            NSLog("MANZO Phase 2: manzo_open returned null for \(mp3Path)")
            return
        }

        // Start playback — manzo_play returns 0 on success, non-zero on error
        let playResult = manzo_play(handle)
        if playResult == 0 {
            NSLog("MANZO Phase 2: playback started — \(mp3Path)")
        } else {
            NSLog("MANZO Phase 2: manzo_play failed with code \(playResult)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release Rust handle on app exit — manzo_close drops the Arc and stops cpal stream (T-02-09)
        if let handle = manzoHandle {
            manzo_close(handle)
            manzoHandle = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
