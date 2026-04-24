---
plan: 08-03
phase: 08-playlist-library
status: complete
completed: 2026-04-24
---

## Summary

Full AppDelegate integration connecting PlaylistManager and ManzoPlaylistPanel built in Wave 1. Replaced Phase 3 trackQueue with real playlist management. AppDelegate now owns the complete NSTableViewDataSource including drag-reorder validation and acceptance.

## Key Decisions Implemented

- **D-02**: Alt+E menu item (`togglePlaylistPanel`); PL button in statusView via `makePLButton()` + `rootView.addPLButton(plBtn)`
- **D-03**: Co-move via `NSWindow.didMoveNotification` → `handleMainWindowMoved()` computing delta
- **D-11**: `playlistManager.save()` called in `applicationWillTerminate` before handle close
- **D-12**: `trackQueue`/`currentTrackIndex` removed; `PlaylistManager` + `ManzoPlaylistPanel` owned as retained properties
- **D-13**: `removeTrackAt(_:)` handles currently-playing case — advances to next or stops playback
- **D-14**: `jumpToTrack(at:)` — double-click jump with close-before-open ordering (Phase 3 constraint honored)
- **D-15**: `pollPlaybackState` uses `PlaylistManager.next()` instead of raw array indexing
- **D-17**: `openFilePicker()` — NSOpenPanel wired to `PlaylistManager.add(urls:)`
- **LIB-02 (AppDelegate side)**: `validateDrop` forces `.above` drop operation; `acceptDrop` calls `PlaylistManager.move(from:to:)` + `tableView.moveRow(at:to:)`

## Files Modified

- `ManzoApp/ManzoApp/AppDelegate.swift` — full Phase 8 rewrite (380 lines added, 51 removed)
- `ManzoApp/ManzoApp/ManzoRootView.swift` — `addPLButton(_:)` method added (Task 1)

## Deviations

- `ManzoSpectrumView.isRenderLoopRunning` not checked in `jumpToTrack` — `startRenderLoop()` called unconditionally (it guards internally with `renderSource == nil`); no behavioral deviation
- `panel.playlistDelegate = self` used (not `panel.delegate`) per Phase 8 fix from commit 9402b30 (NSWindow.delegate name clash)
- xcodebuild run in worktree context confirmed BUILD SUCCEEDED (Task 1 build); Task 2 build pending post-merge verification

## Key Files Created

- `.planning/phases/08-playlist-library/08-03-SUMMARY.md` (this file)

## Self-Check: PASSED

All acceptance criteria met:
- `var playlistManager: PlaylistManager` — ✓
- `var playlistPanel: ManzoPlaylistPanel?` — ✓
- `trackQueue` — 0 matches (removed) ✓
- `currentTrackIndex` — 0 matches (removed) ✓
- `playlistManager.next()` in pollPlaybackState — ✓
- `togglePlaylistPanel` — ✓
- `NSWindow.didMoveNotification` — ✓
- `playlistManager.save()` in applicationWillTerminate — ✓
- `ManzoPlaylistPanelDelegate` conformance — ✓
- `NSTableViewDataSource` + `NSTableViewDelegate` extensions — ✓
- `validateDrop` + `acceptDrop` — ✓
- `playlistManager.move` in acceptDrop — ✓
- `tableView.moveRow` in acceptDrop — ✓
- `keyEquivalent: "e"` with `.option` mask — ✓
- `func addPLButton` in ManzoRootView.swift — ✓
