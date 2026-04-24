# Phase 8: Playlist & Library — Pattern Map

**Mapped:** 2026-04-24
**Files analyzed:** 6 (4 new, 2 modified)
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `ManzoApp/ManzoApp/PlaylistTrack.swift` | model (Codable struct) | file-I/O (JSON) | `ManzoApp/ManzoApp/ManzoVisualStyle.swift` | exact (Codable struct + JSON encode/decode) |
| `ManzoApp/ManzoApp/PlaylistManager.swift` | service/model class | CRUD + file-I/O | `ManzoApp/ManzoApp/ManzoVisualStyle.swift` + `AppDelegate.swift` | role-match |
| `ManzoApp/ManzoApp/ManzoPlaylistPanel.swift` | component (NSPanel subclass) | request-response (user interaction) | `ManzoApp/ManzoApp/ManzoWindow.swift` + `ManzoRootView.swift` | exact (window init, NeoAero layer setup) |
| `ManzoApp/ManzoApp/PlaylistRowView.swift` | component (NSTableCellView) | request-response | `ManzoApp/ManzoApp/ManzoRootView.swift` (NSView subclass + wantsLayer + CALayer) | role-match |
| `ManzoApp/ManzoApp/AppDelegate.swift` (modify) | controller | event-driven + CRUD | self | self |
| `ManzoApp/ManzoApp/ManzoRootView.swift` (modify) | component | request-response | self | self |

---

## Pattern Assignments

### `PlaylistTrack.swift` (Codable struct, file-I/O)

**Analog:** `ManzoApp/ManzoApp/ManzoVisualStyle.swift`

**Imports pattern** (ManzoVisualStyle.swift lines 1–4):
```swift
import AppKit

// MARK: - UserDefaults Key (D-02, CONTEXT.md)
private let kVisualStyleKey = "ManzoVisualStyle"
```
Apply the same import-free pattern — `PlaylistTrack` needs no AppKit import, just `Foundation` for `Codable` and `URL`.

**Codable struct pattern** (ManzoVisualStyle.swift lines 27–36):
```swift
struct ManzoVisualStyle: Codable {
    var panelLayout: PanelLayout
    var colorTheme:  ColorTheme
    var wetFloor:    Bool

    static let `default` = ManzoVisualStyle(
        panelLayout: .unifiedSlab,
        colorTheme:  .winampClassic,
        wetFloor:    false
    )
```
`PlaylistTrack` follows this identical pattern — a plain `struct` conforming to `Codable`, all stored properties with `var`:
```swift
// Target shape:
struct PlaylistTrack: Codable {
    var path:     String
    var artist:   String?
    var title:    String?
    var duration: Double   // seconds
}
```
`artist` and `title` are optional — `nil` encodes as absent key in JSON (forward-compatible per D-09). `duration` is `Double` seconds, `path` is the absolute POSIX path string.

**No load/save on PlaylistTrack itself** — persistence lives in `PlaylistManager`. The struct is a pure value type.

---

### `PlaylistManager.swift` (service class, CRUD + file-I/O)

**Analogs:** `ManzoApp/ManzoApp/ManzoVisualStyle.swift` (JSONEncoder/Decoder pattern) and `ManzoApp/ManzoApp/AppDelegate.swift` (FileManager, trackQueue pattern)

**JSON encode/save pattern** (ManzoVisualStyle.swift lines 51–60):
```swift
// Save to UserDefaults. Fails silently on encode error (should never happen for Codable).
func save() {
    guard let data = try? JSONEncoder().encode(self) else {
        NSLog("MANZO Phase 6: ManzoVisualStyle.save — encode failed (unexpected)")
        return
    }
    UserDefaults.standard.set(data, forKey: kVisualStyleKey)
    NSLog("MANZO Phase 6: ManzoVisualStyle.save — layout=%@, theme=%@, wetFloor=%d",
          panelLayout.rawValue, colorTheme.rawValue, wetFloor ? 1 : 0)
}
```
`PlaylistManager.save()` uses the same guard/try? pattern, but writes to a `FileManager` path instead of UserDefaults:
```swift
// Target shape:
func save() {
    guard let data = try? JSONEncoder().encode(tracks) else {
        NSLog("MANZO Phase 8: PlaylistManager.save — encode failed (unexpected)")
        return
    }
    try? data.write(to: playlistURL, options: .atomic)
    NSLog("MANZO Phase 8: PlaylistManager.save — %d tracks written to %@",
          tracks.count, playlistURL.path)
}
```

**JSON load pattern** (ManzoVisualStyle.swift lines 39–49):
```swift
static func load() -> ManzoVisualStyle {
    guard let data  = UserDefaults.standard.data(forKey: kVisualStyleKey),
          let style = try? JSONDecoder().decode(ManzoVisualStyle.self, from: data)
    else {
        NSLog("MANZO Phase 6: ManzoVisualStyle.load — no persisted style, using default")
        return .default
    }
    NSLog("MANZO Phase 6: ManzoVisualStyle.load — layout=%@, theme=%@",
          style.panelLayout.rawValue, style.colorTheme.rawValue)
    return style
}
```
`PlaylistManager.load()` uses `try? Data(contentsOf: playlistURL)` + `JSONDecoder().decode([PlaylistTrack].self, from: data)`. On failure, `tracks` stays `[]`.

**FileManager path construction** (use `FileManager.default.urls(for:in:)` pattern — no existing analog in codebase, use standard Foundation):
```swift
// Target shape:
private var playlistURL: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("Manzo", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("playlist.json")
}
```

**trackQueue/currentTrackIndex pattern being REPLACED** (AppDelegate.swift lines 22–24):
```swift
// Phase 3 (D-05 / AUDIO-05): 2-track queue and polling timer for auto-advance demo.
private var trackQueue: [String] = []
private var currentTrackIndex: Int = 0
private var pollTimer: Timer? = nil
```
These three lines are removed from AppDelegate. `PlaylistManager` owns `tracks: [PlaylistTrack]` and `currentIndex: Int` instead.

**AVFoundation metadata read pattern** — no existing analog in codebase; use standard Foundation pattern on a background queue:
```swift
// Target shape for PlaylistManager.add(urls:):
func add(urls: [URL]) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        var newTracks: [PlaylistTrack] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            var artist: String? = nil
            var title:  String? = nil
            var duration: Double = 0
            // Read duration
            duration = asset.duration.seconds
            // Read common metadata
            for item in asset.commonMetadata {
                if item.commonKey == .commonKeyArtist, let v = item.stringValue { artist = v }
                if item.commonKey == .commonKeyTitle,  let v = item.stringValue { title  = v }
            }
            newTracks.append(PlaylistTrack(path: url.path, artist: artist, title: title, duration: duration))
        }
        DispatchQueue.main.async { [weak self] in
            self?.tracks.append(contentsOf: newTracks)
            self?.save()
            // caller reloads table
        }
    }
}
```

**NSLog diagnostic convention** (AppDelegate.swift lines 57, 86, 100, 111):
```swift
NSLog("MANZO Phase 3: ...")
NSLog("MANZO Phase 6: ...")
```
All PlaylistManager diagnostics use `NSLog("MANZO Phase 8: PlaylistManager.%@ — ...", ...)`.

---

### `ManzoPlaylistPanel.swift` (NSPanel subclass, request-response)

**Primary analog:** `ManzoApp/ManzoApp/ManzoWindow.swift` (NSWindow subclass init pattern) + `ManzoApp/ManzoApp/ManzoRootView.swift` (NeoAeroLayerFactory, setupPanels, Auto Layout)

**NSWindow/NSPanel init pattern** (ManzoWindow.swift lines 28–45):
```swift
init() {
    super.init(
        contentRect: NSRect(x: 0, y: 0, width: kWindowWidth, height: kWindowHeight),
        styleMask:   [.borderless],
        backing:     .buffered,
        defer:       false
    )

    // D-04: set before orderFront — changing after orderFront causes compositor hiccup.
    isOpaque        = false
    backgroundColor = .clear

    // D-05: shadow and Stage Manager opt-out.
    hasShadow         = true
    collectionBehavior = [.canJoinAllSpaces, .stationary]

    NSLog("MANZO Phase 5: ManzoWindow initialized — 275×116 pt borderless")
}
```
`ManzoPlaylistPanel` replaces `.borderless` with `[.nonactivatingPanel, .resizable]`, fixes width to 275 pt, and uses `NSPanel` as base class. `isOpaque = false` and `backgroundColor = .clear` MUST still be set before `orderFront`.

**canBecomeKey/canBecomeMain pattern** (ManzoWindow.swift lines 20–21):
```swift
override var canBecomeKey:  Bool { true }
override var canBecomeMain: Bool { true }
```
Use the same override in `ManzoPlaylistPanel`.

**NeoAero layer insertion pattern — unified slab** (ManzoRootView.swift lines 124–127):
```swift
case .unifiedSlab:
    let slab = NeoAeroLayerFactory.make(style: style, bounds: bounds)
    layer?.insertSublayer(slab, at: 0)
```

**NeoAero layer insertion pattern — bodyFocus** (ManzoRootView.swift lines 139–147):
```swift
case .bodyFocus:
    let bodyLayer    = NeoAeroLayerFactory.make(style: style, bounds: bodyView.bounds)
    let titleSimple  = NeoAeroLayerFactory.makeSimplified(style: style, bounds: titleView.bounds)
    let statusSimple = NeoAeroLayerFactory.makeSimplified(style: style, bounds: statusView.bounds)
    bodyView.layer?.insertSublayer(bodyLayer,     at: 0)
    titleView.layer?.insertSublayer(titleSimple,  at: 0)
    statusView.layer?.insertSublayer(statusSimple, at: 0)
```
`ManzoPlaylistPanel` uses `bodyFocus` logic: `NeoAeroLayerFactory.make(style:bounds:)` for `bodyView`, `makeSimplified(style:bounds:)` for `titleView` and `toolbarView` (16 pt strips).

**Panel setup / Auto Layout pattern** (ManzoRootView.swift lines 70–103):
```swift
private func setupPanels() {
    for panel in [titleView, bodyView, statusView] {
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        addSubview(panel)
    }

    NSLayoutConstraint.activate([
        titleView.leadingAnchor.constraint(equalTo: leadingAnchor),
        titleView.trailingAnchor.constraint(equalTo: trailingAnchor),
        titleView.topAnchor.constraint(equalTo: topAnchor),
        titleView.heightAnchor.constraint(equalToConstant: kTitleBarHeight),

        statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
        statusView.trailingAnchor.constraint(equalTo: trailingAnchor),
        statusView.bottomAnchor.constraint(equalTo: bottomAnchor),
        statusView.heightAnchor.constraint(equalToConstant: kStatusBarHeight),

        bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
        bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
        bodyView.topAnchor.constraint(equalTo: titleView.bottomAnchor),
        bodyView.bottomAnchor.constraint(equalTo: statusView.topAnchor),
    ])
}
```
`ManzoPlaylistPanel` mirrors this layout for `titleView` (16 pt) / `bodyView` (fills) / `toolbarView` (16 pt). The constraint block is identical — replace `statusView` with `toolbarView` and update heights.

**NSScrollView + NSTableView insertion into bodyView** (pattern from ManzoRootView.addSpectrumView, lines 185–205):
```swift
func addSpectrumView(_ view: ManzoSpectrumView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    bodyView.addSubview(view)

    NSLayoutConstraint.activate([
        view.widthAnchor.constraint(equalToConstant: 225),
        view.heightAnchor.constraint(equalToConstant: 32),
        view.centerXAnchor.constraint(equalTo: bodyView.centerXAnchor),
        view.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
    ])

    bodyView.layoutSubtreeIfNeeded()
    // ...
}
```
For the playlist panel's bodyView, pin NSScrollView to all 4 edges (0 pt margin):
```swift
// Target shape:
scrollView.translatesAutoresizingMaskIntoConstraints = false
bodyView.addSubview(scrollView)
NSLayoutConstraint.activate([
    scrollView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
    scrollView.topAnchor.constraint(equalTo: bodyView.topAnchor),
    scrollView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
])
```

**removeNeoAeroLayers utility** (ManzoRootView.swift lines 248–254) — copy verbatim into ManzoPlaylistPanel for layer cleanup on style changes:
```swift
private func removeNeoAeroLayers(from layer: CALayer?) {
    guard let layer = layer else { return }
    let toRemove = layer.sublayers?.filter {
        ($0.value(forKey: "name") as? String) == "NeoAeroContainer"
    } ?? []
    toRemove.forEach { $0.removeFromSuperlayer() }
}
```

**mouseDown drag pattern** (ManzoRootView.swift lines 280–282):
```swift
override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
}
```
Apply this override to the `titleView`'s content view inside the panel — or, since the panel contentView is `ManzoGlassMaterial` NSVisualEffectView, override `mouseDown` there.

**setFrameAutosaveName pattern** (AppDelegate.swift line 109):
```swift
window.setFrameAutosaveName("ManzoMainWindow")
```
Apply `setFrameAutosaveName("ManzoPlaylistPanel")` on the panel — must be called after `orderFront` per D-12 of Phase 5.

**NSWindowDidMoveNotification for co-move** (no existing analog — new):
```swift
// Target shape in AppDelegate or ManzoPlaylistPanel:
NotificationCenter.default.addObserver(
    forName: NSWindow.didMoveNotification,
    object: manzoWindow,
    queue: .main
) { [weak self] _ in
    // compute delta and move panel
}
```

---

### `PlaylistRowView.swift` (NSTableCellView, request-response)

**Analog:** `ManzoApp/ManzoApp/ManzoRootView.swift` (NSView subclass with wantsLayer + CALayer + NSLayoutAnchor)

**NSView subclass setup pattern** (ManzoRootView.swift lines 46–61):
```swift
override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer   = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true
    setupPanels()
    NSLog("MANZO Phase 5: ManzoRootView initialized — ...")
}
required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }
```
`PlaylistRowView` follows the same init pattern — `NSTableCellView` subclass, `wantsLayer = true`, `required init?(coder:)` with `fatalError`.

**CALayer separator pattern** (from UI-SPEC — 1 pt divider at bottom of row):
```swift
// Target shape in PlaylistRowView.init or setupLayers():
let separator = CALayer()
separator.backgroundColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                    components: [1.0, 1.0, 1.0, 0.06])
separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
layer?.addSublayer(separator)
```

**P3 color construction pattern** (NeoAeroLayer.swift lines 36–44):
```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let specTopWhite = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.50])!
```
All `PlaylistRowView` text colors use this pattern — never `NSColor(red:green:blue:alpha:)`.

**NSTextField subview pattern** (no existing NSTextField in codebase — use standard AppKit):
```swift
// Target shape for row text fields:
let trackLabel = NSTextField(labelWithString: "")
trackLabel.translatesAutoresizingMaskIntoConstraints = false
trackLabel.font = NSFont.systemFont(ofSize: 11)
trackLabel.textColor = NSColor(cgColor: CGColor(colorSpace: p3,
                                components: [0.78, 0.80, 0.85, 1.0])!)
trackLabel.backgroundColor = .clear
trackLabel.isBezeled = false
trackLabel.isEditable = false
addSubview(trackLabel)
```

**NSAttributedString strikethrough for missing files** (new — no existing analog):
```swift
// Target shape:
let attrs: [NSAttributedString.Key: Any] = [
    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
    .foregroundColor: NSColor(cgColor: CGColor(colorSpace: p3,
                              components: [0.50, 0.52, 0.55, 0.70])!)!,
    .font: NSFont.systemFont(ofSize: 11)
]
```

---

## Modifications to Existing Files

### `AppDelegate.swift` — what changes and what stays

**Lines removed (3 properties, lines 22–24):**
```swift
// REMOVE all three:
private var trackQueue: [String] = []
private var currentTrackIndex: Int = 0
// pollTimer stays — just wired differently
```

**New property declarations to add** (after `spectrumView` at line 35, following the same retained-reference pattern):
```swift
// Pattern: existing retained-reference declarations (lines 8, 28, 32, 35):
private var manzoHandle:  UnsafeMutablePointer<manzo_ManzoHandle>? = nil
private var manzoWindow:  ManzoWindow? = nil
private var visualStyle:  ManzoVisualStyle = .default
private var spectrumView: ManzoSpectrumView? = nil
// Add similarly:
private var playlistManager:   PlaylistManager = PlaylistManager()
private var playlistPanel:     ManzoPlaylistPanel? = nil
```

**applicationDidFinishLaunching — trackQueue section replaced** (lines 48–88):

The existing block:
```swift
trackQueue = [
    resolveFixturePath(name: "test",  ext: "mp3"),
    resolveFixturePath(name: "test2", ext: "mp3"),
]
let firstPath = trackQueue[currentTrackIndex]
if !FileManager.default.fileExists(atPath: firstPath) {
    NSLog("MANZO Phase 3: first track not found at \(firstPath) — skipping playback")
} else {
    manzoHandle = manzo_open(firstPath)
    ...
    pollTimer = Timer.scheduledTimer(...)
}
```
Is replaced with PlaylistManager.load() + play first track if any. Timer start pattern stays identical:
```swift
pollTimer = Timer.scheduledTimer(
    timeInterval: 0.1,
    target: self,
    selector: #selector(pollPlaybackState),
    userInfo: nil,
    repeats: true
)
```

**pollPlaybackState — replacement pattern** (lines 149–197 — the entire method body changes):

Old queue cursor advance (lines 163–196):
```swift
currentTrackIndex += 1
guard currentTrackIndex < trackQueue.count else {
    NSLog("MANZO Phase 3: queue exhausted (\(currentTrackIndex)/\(trackQueue.count)) — stopping poll timer")
    pollTimer?.invalidate()
    pollTimer = nil
    spectrumView?.stopRenderLoop()
    return
}
let nextPath = trackQueue[currentTrackIndex]
```
New pattern calls `playlistManager.next()` and reads `track.path`. The spectrumView nil-before-close pattern (lines 159–163) stays verbatim:
```swift
// KEEP verbatim (lines 159–163):
spectrumView?.manzoHandle = nil
manzo_close(handle)
manzoHandle = nil

// REPLACE queue indexing with:
guard let nextTrack = playlistManager.next() else {
    NSLog("MANZO Phase 8: PlaylistManager exhausted — stopping poll timer")
    pollTimer?.invalidate()
    pollTimer = nil
    spectrumView?.stopRenderLoop()
    return
}
let nextPath = nextTrack.path
```

**applicationWillTerminate — add save call** (after line 129, before handle close):
```swift
// Existing:
pollTimer?.invalidate()
pollTimer = nil
spectrumView?.stopRenderLoop()
// Add:
playlistManager.save()
// Then existing:
if let handle = manzoHandle { manzo_close(handle); manzoHandle = nil }
```

**buildMainMenu — add Playlist Editor menu item** (after windowMenu section, lines 251–274):

The pattern for adding a menu item with modifier mask (lines 236–239):
```swift
let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                 action: #selector(NSApplication.hideOtherApplications(_:)),
                                 keyEquivalent: "h")
hideOthers.keyEquivalentModifierMask = [.command, .option]
```
Apply same pattern for Alt+E:
```swift
// Target shape — add inside windowMenu or a new View menu:
let plItem = windowMenu.addItem(withTitle: "Playlist Editor",
                                action: #selector(togglePlaylistPanel),
                                keyEquivalent: "e")
plItem.keyEquivalentModifierMask = [.option]
```

---

### `ManzoRootView.swift` — PL button addition

**Where to add** (in `statusView`, trailing side — following the addSpectrumView pattern for adding subviews):

```swift
// Pattern from addSpectrumView (lines 185–200):
view.translatesAutoresizingMaskIntoConstraints = false
bodyView.addSubview(view)
NSLayoutConstraint.activate([...])
```
PL button follows same TALC pattern but in `statusView`. Add a `func addPLButton(_ button: NSButton)` method mirroring `addSpectrumView`:
```swift
// Target shape:
func addPLButton(_ button: NSButton) {
    button.translatesAutoresizingMaskIntoConstraints = false
    statusView.addSubview(button)
    NSLayoutConstraint.activate([
        button.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -8),
        button.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
        button.widthAnchor.constraint(equalToConstant: 20),
        button.heightAnchor.constraint(equalToConstant: 12),
    ])
    NSLog("MANZO Phase 8: PL button added to statusView")
}
```

---

## Shared Patterns

### NSVisualEffectView single-root rule
**Source:** `ManzoApp/ManzoApp/ManzoRootView.swift` lines 3–12 (comment block)
**Apply to:** `ManzoPlaylistPanel.swift` (panel root), `PlaylistRowView.swift`

The panel root content view IS the single `.behindWindow` `NSVisualEffectView`. No inner subview may be an `NSVisualEffectView`. All inner panels (`titleView`, `bodyView`, `toolbarView`) are plain `NSView` with `wantsLayer = true`.

```swift
// ManzoRootView.swift lines 50–55 — the single .behindWindow root:
material     = ManzoGlassMaterial
blendingMode = .behindWindow
state        = .active
wantsLayer   = true
layer?.cornerRadius = 10
layer?.masksToBounds = true
```

### P3 Color Construction
**Source:** `ManzoApp/ManzoApp/NeoAeroLayer.swift` lines 36–44
**Apply to:** `PlaylistRowView.swift`, `ManzoPlaylistPanel.swift`
```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let color = CGColor(colorSpace: p3, components: [r, g, b, a])!
```
Never use `NSColor(red:green:blue:alpha:)` or `CGColor(gray:alpha:)` for brand colors.

### NeoAeroLayerFactory.make / makeSimplified
**Source:** `ManzoApp/ManzoApp/NeoAeroLayer.swift` lines 105–202
**Apply to:** `ManzoPlaylistPanel.swift`

Full chrome (`make`) for `bodyView`. Simplified chrome (`makeSimplified`) for `titleView` (16 pt) and `toolbarView` (16 pt). Both return a container tagged "NeoAeroContainer". Insert at index 0 of the target layer's sublayers.

```swift
// Full chrome (NeoAeroLayer.swift line 105):
static func make(style: ManzoVisualStyle, bounds: CGRect) -> CALayer

// Simplified chrome (NeoAeroLayer.swift line 168):
static func makeSimplified(style: ManzoVisualStyle, bounds: CGRect) -> CALayer
```

### shouldRasterize Retina pairing
**Source:** `ManzoApp/ManzoApp/NeoAeroLayer.swift` lines 149–151 (and 193–195)
**Apply to:** All CALayer containers in `ManzoPlaylistPanel.swift`
```swift
container.shouldRasterize    = true
container.rasterizationScale = 2.0
```
These two lines MUST always appear together. Never set `shouldRasterize = true` without `rasterizationScale = 2.0`.

### Auto Layout constraint activation
**Source:** `ManzoApp/ManzoApp/ManzoRootView.swift` lines 82–100
**Apply to:** `ManzoPlaylistPanel.swift`, `PlaylistRowView.swift`, `ManzoRootView.swift` (PL button)
```swift
panel.translatesAutoresizingMaskIntoConstraints = false
// ...
NSLayoutConstraint.activate([
    view.leadingAnchor.constraint(equalTo: leadingAnchor),
    // etc.
])
```
All constraints via `NSLayoutAnchor`. No `frame`-based layout for NSViews. The `translatesAutoresizingMaskIntoConstraints = false` line is mandatory before any anchor constraint.

### NSLog diagnostic convention
**Source:** Every file — e.g., AppDelegate.swift lines 57, 86, 100
**Apply to:** All Phase 8 files
```swift
NSLog("MANZO Phase 8: <ClassName>.<methodName> — <message>")
```

### ManzoVisualStyle.load() for style access
**Source:** `ManzoApp/ManzoApp/ManzoVisualStyle.swift` lines 39–49
**Apply to:** `ManzoPlaylistPanel.swift` (needs the style to call NeoAeroLayerFactory)

The panel reads `ManzoVisualStyle.load()` or receives the style from AppDelegate. The same style that drives the main window drives the panel — no separate style loading.

### Codable JSON encode/decode
**Source:** `ManzoApp/ManzoApp/ManzoVisualStyle.swift` lines 51–60 and 39–49
**Apply to:** `PlaylistManager.swift`
```swift
// Encode:
guard let data = try? JSONEncoder().encode(tracks) else { return }
try? data.write(to: playlistURL, options: .atomic)

// Decode:
guard let data  = try? Data(contentsOf: playlistURL),
      let list  = try? JSONDecoder().decode([PlaylistTrack].self, from: data)
else { return }
tracks = list
```

### required init?(coder:) fatalError
**Source:** `ManzoRootView.swift` line 63, `ManzoSpectrumView.swift` line 76
**Apply to:** `ManzoPlaylistPanel.swift`, `PlaylistRowView.swift`
```swift
required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `PlaylistRowView.swift` (NSTableView drag-reorder API) | component | event-driven | No NSTableView or drag-reorder exists in codebase; use `NSDraggingSession`-based `NSTableView` datasource/delegate pattern from Apple docs |
| `PlaylistManager.add(urls:)` AVFoundation metadata read | service method | file-I/O | No AVFoundation usage exists; use standard `AVURLAsset.commonMetadata` on background DispatchQueue |
| Co-move `NSWindowDidMoveNotification` subscription | AppDelegate method | event-driven | No window notification observation exists; new pattern |
| NSOpenPanel file picker | AppDelegate/panel method | request-response | No NSOpenPanel usage exists; standard AppKit pattern |

---

## Concrete Color Values (copy-ready for PlaylistRowView and ManzoPlaylistPanel)

All from UI-SPEC.md, expressed as P3 CGColor components:

```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
// Row body text (normal):
let rowTextNormal  = CGColor(colorSpace: p3, components: [0.78, 0.80, 0.85, 1.0])!
// Row body text (active/playing):
let rowTextActive  = CGColor(colorSpace: p3, components: [1.00, 1.00, 1.00, 1.0])!
// Row body text (missing file):
let rowTextMissing = CGColor(colorSpace: p3, components: [0.50, 0.52, 0.55, 0.70])!
// Row selection background:
let rowSelectionBg = CGColor(colorSpace: p3, components: [0.20, 0.40, 0.65, 0.40])!
// Row separator:
let rowSeparator   = CGColor(colorSpace: p3, components: [1.00, 1.00, 1.00, 0.06])!
// Toolbar button/label text (secondary/dim):
let toolbarLabel   = CGColor(colorSpace: p3, components: [0.58, 0.60, 0.65, 1.0])!
// Drop indicator line:
let dropIndicator  = CGColor(colorSpace: p3, components: [0.20, 0.40, 0.65, 0.80])!
// PL button text (inactive):
let plButtonInactive = CGColor(colorSpace: p3, components: [0.78, 0.80, 0.85, 0.70])!
// PL button text (active):
let plButtonActive   = CGColor(colorSpace: p3, components: [1.00, 1.00, 1.00, 1.0])!
// PL button background (active):
let plButtonActiveBg = CGColor(colorSpace: p3, components: [0.20, 0.40, 0.65, 0.50])!
```

---

## Metadata

**Analog search scope:** `/Users/usameak42/Coding/MANZO/ManzoApp/ManzoApp/`
**Files scanned:** 7 Swift files (all files in ManzoApp)
**Pattern extraction date:** 2026-04-24
