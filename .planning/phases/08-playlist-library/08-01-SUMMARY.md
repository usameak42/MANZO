---
phase: 08-playlist-library
plan: "01"
subsystem: model
tags: [swift, avfoundation, codable, json, playlist, persistence]

requires:
  - phase: 03-playback-controls
    provides: trackQueue/currentTrackIndex pattern being replaced by PlaylistManager

provides:
  - PlaylistTrack Codable struct with path/artist?/title?/duration + computed display helpers
  - PlaylistManager class with full CRUD API + AVFoundation metadata read + atomic JSON persistence

affects:
  - 08-02-PLAN.md (PlaylistPanel UI uses PlaylistManager.tracks + PlaylistTrack.displayTitle)
  - 08-03-PLAN.md (AppDelegate wiring replaces trackQueue with playlistManager instance)

tech-stack:
  added: [AVFoundation (commonMetadata, AVURLAsset)]
  patterns:
    - Codable struct + extension separation to preserve synthesized CodingKeys
    - Atomic JSON write via Data.write(to:options:.atomic) to Application Support directory
    - DispatchQueue.global background read + DispatchQueue.main.async append for AVFoundation I/O

key-files:
  created:
    - ManzoApp/ManzoApp/PlaylistTrack.swift
    - ManzoApp/ManzoApp/PlaylistManager.swift
  modified: []

key-decisions:
  - "D-09 JSON schema implemented: path/artist?/title?/duration persisted to ~/Library/Application Support/Manzo/playlist.json"
  - "D-07 AVFoundation metadata read on DispatchQueue.global(qos:.userInitiated) background queue"
  - "D-11 autosave on every mutation: add/remove/move all call save()"
  - "D-12 full public API surface: add/remove/move/next/trackAt/save/load"
  - "Computed properties on extension (not inside struct body) to keep Codable synthesis clean"
  - "onAdded: (() -> Void)? closure added to add(urls:) for NSTableView reload notification"

patterns-established:
  - "PlaylistTrack extension pattern: computed props outside Codable struct body for clean synthesis"
  - "PlaylistManager init() calls load() — restore state on construction, empty if missing"
  - "NaN/negative guard on AVURLAsset.duration.seconds before storing as Double"

requirements-completed:
  - LIB-01
  - LIB-03
  - LIB-04

duration: 2min
completed: "2026-04-24"
---

# Phase 8 Plan 01: PlaylistTrack + PlaylistManager Model Layer Summary

**Foundation-only model layer: Codable PlaylistTrack struct + PlaylistManager class with AVFoundation tag read, atomic JSON persistence to Application Support, and full 7-method CRUD API replacing the Phase 3 trackQueue.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-24T07:30:38Z
- **Completed:** 2026-04-24T07:32:37Z
- **Tasks:** 2
- **Files modified:** 2 (both new)

## Accomplishments

- PlaylistTrack Codable+Equatable struct with optional artist/title, Double duration, and three computed display properties (isMissingFile, displayTitle, formattedDuration) on a separate extension
- PlaylistManager with complete D-12 public API: add(urls:) reads AVFoundation commonMetadata on background queue and appends on main thread, remove(at:) correctly adjusts currentIndex for all three cases, move(from:to:) reorders with correct index tracking, next() returns nil on playlist exhaustion
- Atomic JSON persistence to ~/Library/Application Support/Manzo/playlist.json with directory auto-creation; load() called from init() for seamless restore
- xcodebuild passes — both files picked up by xcodegen sources glob with no project.yml edits

## Task Commits

1. **Task 1: PlaylistTrack Codable struct** - `98a4986` (feat)
2. **Task 2: PlaylistManager service class** - `25e6f17` (feat)

## Files Created/Modified

- `ManzoApp/ManzoApp/PlaylistTrack.swift` — Codable+Equatable struct with path/artist?/title?/duration; extension adds isMissingFile/displayTitle/formattedDuration; Foundation-only
- `ManzoApp/ManzoApp/PlaylistManager.swift` — final class with full CRUD + AVFoundation tag read + atomic JSON save/load; Foundation + AVFoundation only

## Decisions Made

- `onAdded: (() -> Void)?` closure added to `add(urls:)` beyond the D-12 spec to allow the caller (NSTableView) to reload data after background metadata read completes — no spec conflict, additive only
- NaN/negative guard applied to `asset.duration.seconds` before storing (plan specified this as inline comment but made it explicit code for correctness)
- Computed properties placed on `PlaylistTrack` extension (not inside struct body) to preserve Codable synthesis clean without CodingKeys pollution

## Deviations from Plan

None — plan executed exactly as written. The `onAdded` closure is an additive parameter (optional, default nil) that the plan text implied but did not explicitly enumerate in D-12.

## Issues Encountered

None — xcodebuild passed on first run.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundary crossings introduced beyond those documented in the plan's threat model (T-08-01 through T-08-04). All paths are within the app's Application Support directory.

## Known Stubs

None — PlaylistManager and PlaylistTrack are pure model code with no UI. Data flows from real AVFoundation reads and real disk I/O.

## Self-Check

Checking created files exist:

- ManzoApp/ManzoApp/PlaylistTrack.swift — FOUND
- ManzoApp/ManzoApp/PlaylistManager.swift — FOUND

Checking commits exist:

- 98a4986 (PlaylistTrack) — FOUND
- 25e6f17 (PlaylistManager) — FOUND

## Self-Check: PASSED

## Next Phase Readiness

- Plan 08-02 (PlaylistPanel UI) can now import PlaylistTrack and PlaylistManager directly — both files present in xcodegen sources glob
- Plan 08-03 (AppDelegate wiring) can replace trackQueue/currentTrackIndex with PlaylistManager instance and call playlistManager.next() in pollPlaybackState
- Phase 9 JSON forward-compatibility maintained: PlaylistTrack fields use optional artist/title; adding optional `url: String?` will decode existing entries cleanly

---
*Phase: 08-playlist-library*
*Completed: 2026-04-24*
