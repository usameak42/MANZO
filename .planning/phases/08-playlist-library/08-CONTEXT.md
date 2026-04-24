# Phase 8: Playlist & Library - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a persistent playlist system — a separate floating NSPanel where users can add files
via NSOpenPanel, reorder by drag-and-drop, remove tracks, and find their playlist restored
on next launch. The Phase 3 `trackQueue: [String]` placeholder in AppDelegate is replaced
by a real `PlaylistManager` class.

**In scope:**
- `ManzoPlaylistPanel` — separate 275×116 pt resizable NSPanel, docked below the main window
- `PlaylistManager` — model class owned by AppDelegate (tracks, currentIndex, add/remove/reorder, JSON persistence)
- `PlaylistTrack` — model struct (`{path, artist, title, duration}`)
- NSOpenPanel file picker (MP3 only, multi-select)
- NSTableView with Winamp-style row rendering + drag-reorder
- Three track removal methods (Delete key, right-click menu, [-] toolbar button)
- JSON persistence at `~/Library/Application Support/Manzo/playlist.json`
- Co-move behavior (panel follows main window on drag)
- Toggle via Alt+E shortcut + PL button in main window chrome
- Missing-file display (strikethrough, kept in list)

**Out of scope:**
- EQ slider UI — still pending
- Online streaming (URL tracks) — Phase 9 extends PlaylistTrack with a `url` field
- Non-MP3 formats (FLAC, AAC, etc.) — v2
- Transport control buttons in main window chrome — separate concern
- `.wsz` skin-driven playlist styling — v2

</domain>

<decisions>
## Implementation Decisions

### Window Architecture
- **D-01:** The playlist editor is a **separate `NSPanel`** — not embedded in the main 275×116
  window. Winamp canonical dimensions (from `Winamp/Src/winamp/config.h:120`):
  `config_pe_width = 275`, `config_pe_height = 116`. The panel opens at the same width
  (275 pt fixed) but is **vertically resizable** — users stretch it taller to see more tracks.
  Initial position: directly below the main window `(mainWindow.frame.origin.x, mainWindow.frame.origin.y - panelHeight)`.

- **D-02:** Panel toggle — **two methods, both required:**
  1. **Alt+E keyboard shortcut** (Winamp default `config_pe_open` toggle)
  2. **PL button in main window chrome** (small button, likely in `statusView` or `titleView`)
  Both show/hide the panel. Panel state (open/closed) persists between launches.

- **D-03:** **Co-move behavior** — when the main window moves, the playlist panel moves with it,
  preserving the relative offset. Observe `NSWindowDidMoveNotification` on the main window;
  compute `delta = newMainOrigin − oldMainOrigin` and apply to panel origin.
  No magnetic snap logic needed (deferred to v2).

- **D-04:** Panel is resizable vertically (user can stretch it taller). Width stays locked at 275 pt.
  Panel position and size persisted between launches via `setFrameAutosaveName("ManzoPlaylistPanel")`.

- **D-05:** Panel uses the same visual aesthetic as the main window — NeoAero chrome via
  `NeoAeroLayerFactory`, `ManzoGlassMaterial` NSVisualEffectView at root, CALayer-only inner
  panels. The NSTableView lives in the body area of the panel.

### Track Display Format
- **D-06:** Each playlist row renders in **Winamp classic format**:
  ```
  {rowNum}. {Artist} – {Title}  [{MM:SS}]
  ```
  Fallback when ID3 tags are absent: `{rowNum}. {filename_no_ext}  [{MM:SS}]`

- **D-07:** **ID3 metadata read at add time** using `AVFoundation.AVURLAsset.commonMetadata`.
  Extract `commonKeyArtist`, `commonKeyTitle`, and asset duration. Store in `PlaylistTrack`
  and write to JSON — no re-read on launch. If AVFoundation cannot extract tags, `artist` and
  `title` are `nil` (fallback to filename triggers).

- **D-08:** **Active track marker**: the currently playing row renders with **bold text + ▶ symbol**
  on the left side of the row. No row background tint — consistent with the dark CALayer aesthetic.
  When a new track starts, the old active marker is cleared.

### Persistence Format
- **D-09:** Playlist saved as **JSON** at:
  `~/Library/Application Support/Manzo/playlist.json`
  Track entry schema:
  ```json
  {
    "path": "/absolute/path/to/file.mp3",
    "artist": "Radiohead",
    "title": "Creep",
    "duration": 238.5
  }
  ```
  `artist` and `title` are nullable (absent = filename fallback). `duration` is in seconds
  (Double). Phase 9 will add a nullable `"url"` field for streaming entries — JSON schema
  is forward-compatible.

- **D-10:** **Missing files at launch**: if a track's path no longer resolves on disk, keep the
  track entry in the playlist with **strikethrough text**. Do NOT auto-remove. User removes
  manually. Prevents accidental loss of tracks on unmounted external drives.

- **D-11:** JSON **autosaves after every mutation** (add, remove, reorder). Debounce/coalesce
  rapid reorders is Claude's discretion — correctness over performance.

### PlaylistManager & AppDelegate Wiring
- **D-12:** `PlaylistManager` is a **dedicated class owned by AppDelegate**. Public API:
  - `var tracks: [PlaylistTrack]`
  - `var currentIndex: Int`
  - `func add(urls: [URL])` — reads ID3 tags, appends to list, saves JSON
  - `func remove(at index: Int)` — removes track, updates currentIndex if needed, saves JSON
  - `func move(from: Int, to: Int)` — reorder, saves JSON
  - `func next() -> PlaylistTrack?` — returns next track (wraps or stops at end)
  - `func trackAt(_ index: Int) -> PlaylistTrack?`
  - `func save()` / `func load()`
  The existing `AppDelegate.trackQueue: [String]` and `currentTrackIndex: Int` are **removed**
  and replaced by `PlaylistManager`.

- **D-13:** **Three removal methods** — all call `PlaylistManager.remove(at:)`:
  1. **Delete key** on selected NSTableView row
  2. **Right-click context menu** → "Remove from Playlist"
  3. **[-] button** in the playlist panel's bottom toolbar
  If the removed track is currently playing: advance to next (or stop if last track).

- **D-14:** **Double-click a row** → jump to that track immediately. Close current handle via
  `manzo_close`, set `PlaylistManager.currentIndex` to the clicked row, open + play the new
  track via `manzo_open` + `manzo_play`. Update the active track marker.

- **D-15:** The **100ms poll timer** in AppDelegate (`pollPlaybackState`) is updated to call
  `PlaylistManager.next()` when `MANZO_STATE_ENDED` is detected, instead of advancing a raw
  array index. Timer logic and spectrum handle re-wiring remain the same.

- **D-16:** The playlist panel's **bottom toolbar** contains at minimum:
  - **[+] Add** button — triggers NSOpenPanel
  - **[-] Remove** button — removes selected row (calls `PlaylistManager.remove(at:)`)
  - Track count display (e.g. "12 tracks") — Claude's discretion on placement

### File Picker
- **D-17:** NSOpenPanel with `allowsMultipleSelection = true`, `canChooseFiles = true`,
  `canChooseDirectories = false`. `allowedContentTypes = [.mp3]` (Phase 8 is MP3-only;
  other UTTypes deferred to v2). Selected URLs passed to `PlaylistManager.add(urls:)`.

### Claude's Discretion
- Whether `ManzoPlaylistPanel` is an `NSPanel` subclass or a plain `NSWindow` with `.nonactivatingPanel` behavior
- Exact NSTableView cell rendering (custom `NSTableCellView` subclass or attributed string in `NSTextField`)
- NSTableView drag-and-drop API choice (older `tableView:writeRowsWithIndexes:toPasteboard:` vs newer `NSDraggingSession` approach)
- Debounce strategy for JSON autosave during rapid drag-reorder
- Co-move notification cleanup on app termination
- Exact placement of the PL button in the main window chrome (statusView vs titleView)
- Whether the panel shows an empty-state message ("Add tracks with [+] or drag files here") when the playlist is empty

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Winamp Source (playlist window reference)
- `Winamp/Src/winamp/config.h:120-121` — `config_pe_width = 275`, `config_pe_height = 116`
  (canonical playlist editor default dimensions), `config_pe_wx = 26`, `config_pe_wy = 261`
  (default position below main window), `config_pe_open = 1` (default open)
- `Winamp/Src/winamp/draw_pe.cpp` — Winamp playlist editor rendering: row format, button layout,
  vertical scrollbar positioning. Use as visual reference for the panel layout.
- `Winamp/Src/winamp/Main.h:71-72` — `WINDOW_WIDTH 275`, `WINDOW_HEIGHT 116` (main window dims)

### Existing Swift Code (integration points — MUST read)
- `ManzoApp/ManzoApp/AppDelegate.swift` — `trackQueue`, `currentTrackIndex`, `pollPlaybackState`,
  and spectrum handle re-wiring. All of this changes in Phase 8. Read the full file before planning.
- `ManzoApp/ManzoApp/ManzoRootView.swift` — `titleView`, `bodyView`, `statusView` layout.
  PL button is added as a subview of `statusView` or `titleView`. Read `setupPanels()` and
  `addSpectrumView()` for the established pattern.
- `ManzoApp/ManzoApp/ManzoWindow.swift` — The NSWindow subclass. Co-move logic hooks here or
  in AppDelegate via `NSWindowDidMoveNotification`. Read for window setup patterns.
- `ManzoApp/ManzoApp/NeoAeroLayer.swift` — `NeoAeroLayerFactory` for applying the visual chrome
  to the playlist panel. Reuse directly.
- `ManzoApp/ManzoApp/ManzoVisualStyle.swift` — `ManzoVisualStyle` data model, loaded by
  AppDelegate. The playlist panel should use the same style.

### Prior Phase Context (decisions that carry into Phase 8)
- `.planning/phases/05-ui-shell/05-CONTEXT.md` — D-03 (275×116 pt window), D-04 (isOpaque=false
  before orderFront), D-05 (hasShadow, collectionBehavior), D-07 (single .behindWindow rule),
  D-08/D-09 (panel structure, CALayer-only), D-10 (Auto Layout + NSLayoutAnchor), D-12
  (setFrameAutosaveName pattern)
- `.planning/phases/03-playback-controls/03-CONTEXT.md` — D-02 (manzo_get_state values 1–4),
  D-05 (gapless policy, silence gap acceptable), and the close-before-open ordering for track
  transitions

### Project Planning
- `.planning/REQUIREMENTS.md` — LIB-01, LIB-02, LIB-03, LIB-04 (the four Phase 8 requirements)
- `.planning/ROADMAP.md` — Phase 8 success criteria (4 items)
- `.planning/PROJECT.md` — P3 colors, CALayer-only panels, Auto Layout conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `NeoAeroLayerFactory` (`NeoAeroLayer.swift`) — Apply to the playlist panel's root layer
  and body/title/status subviews. Identical call pattern to the main window.
- `ManzoVisualStyle.load()` — Returns the persisted style. Playlist panel reads the same style
  so both windows share the same visual theme.
- `AppDelegate.pollPlaybackState()` — The 100ms timer. Phase 8 modifies this method's body
  to use `PlaylistManager.next()` instead of raw array indexing.
- `AppDelegate.resolveFixturePath(name:ext:)` — Keep as-is; Phase 8 tracks are user-selected,
  not fixtures, but this helper may remain for testing.
- `ManzoRootView.addSpectrumView()` — Pattern for adding a subview with NSLayoutAnchor
  constraints into an existing panel. Follow this for adding NSTableView into the playlist panel.

### Established Patterns
- `NSLog(...)` for all diagnostic output (all phases)
- No NIBs/storyboards — all UI in code
- `setFrameAutosaveName(_:)` for window/panel position persistence (D-12, Phase 5)
- `translatesAutoresizingMaskIntoConstraints = false` + `NSLayoutAnchor` for all Auto Layout
- `wantsLayer = true` + `isOpaque = false` on all inner panel NSViews
- `project.yml` (xcodegen) — new Swift files are picked up automatically by the
  `sources: path: ManzoApp` glob; no manual project.yml edits needed for new `.swift` files

### Integration Points
- `AppDelegate.applicationDidFinishLaunching` — PlaylistManager initialization, panel creation,
  and PL button wiring all go here
- `AppDelegate.applicationWillTerminate` — `PlaylistManager.save()` called here as a final
  save before exit (in addition to autosave on mutation)
- `ManzoRootView.statusView` (or `titleView`) — PL toggle button added as a subview here
- `ManzoWindow` — `NSWindowDidMoveNotification` subscription for co-move behavior

</code_context>

<specifics>
## Specific Ideas

- Winamp playlist window `config_pe_height_ws` (windowshade height) is also stored — deferred
  to v2 when windowshade mode is implemented
- JSON schema is forward-compatible: Phase 9 adds `"url": String?` to `PlaylistTrack` without
  breaking existing entries (existing entries have no `url` key → treated as local files)
- Winamp's Alt+E binding: `AppDelegate.buildMainMenu()` already has the main menu wired —
  add a "Playlist Editor" menu item with `keyEquivalent: "e"` and `.option` modifier mask
- The `resolveFixturePath` 2-track queue in AppDelegate gets replaced by `PlaylistManager.load()`;
  on very first launch (empty JSON) the playlist starts empty — no auto-load of test fixtures
- AVFoundation duration for MP3: `AVURLAsset(url:).duration.seconds` — note this triggers
  a network/disk access, so run on a background queue and reload the table cell when done

</specifics>

<deferred>
## Deferred Ideas

- Magnetic snap behavior (playlist panel auto-aligns when dragged near main window) — v2.
  Winamp's `embwnd.cpp` snap logic is the reference when this ships.
- Non-MP3 file formats (FLAC, AAC, OGG) — v2 (`ADVAUDIO-01`)
- Transport control buttons (play/pause/stop/seek UI) in the main window chrome — separate concern,
  not in Phase 8 scope
- Windowshade mode for the playlist panel — v2
- Playlist sorting (by title, artist, duration) — backlog
- Duplicate detection on add — backlog
- Drag files from Finder directly into playlist panel — backlog (nice-to-have; NSTableView
  accepts `NSFilenamesPboardType` drops with moderate effort)

</deferred>

---

*Phase: 08-playlist-library*
*Context gathered: 2026-04-24*
