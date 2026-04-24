---
phase: 08-playlist-library
reviewed: 2026-04-24T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - ManzoApp/ManzoApp/PlaylistTrack.swift
  - ManzoApp/ManzoApp/PlaylistManager.swift
  - ManzoApp/ManzoApp/ManzoPlaylistPanel.swift
  - ManzoApp/ManzoApp/PlaylistRowView.swift
  - ManzoApp/ManzoApp/AppDelegate.swift
  - ManzoApp/ManzoApp/ManzoWindow.swift
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-04-24
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 8 delivers a functioning NSTableView playlist panel with PlaylistManager CRUD, JSON persistence, drag-reorder, and three removal paths. The architecture is sound and the CLAUDE.md constraints (single .behindWindow NSVisualEffectView, P3 colors everywhere, no int16 in audio path) are followed correctly throughout. Two critical issues were found: a dangling-pointer window (use-after-free class) in `pollPlaybackState` where `manzoHandle` is closed and then immediately read again via the captured `handle` binding, and a force-unwrap of `manzoWindow!` in `openFilePicker` that will crash if called before `applicationDidFinishLaunching` completes or after the window is released. Five warnings cover logic gaps: `currentIndex` is not persisted in JSON so playback position is lost on relaunch; `pollPlaybackState` skips missing-file tracks instead of advancing; `removeTrackAt` has an off-by-one risk when the removed track is current and the playlist is now empty; the marquee's skip-if-running guard compares only the last keyframe value rather than the overflow amount (CGFloat cast from NSNumber), so overflow changes on row reuse may not restart the animation correctly; and `acceptDrop` calls both `moveRow` and `reloadData`, making the NSTableView animation flash. Four info-level items are also noted.

---

## Critical Issues

### CR-01: Dangling handle read in `pollPlaybackState` — use-after-free class

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:186–197`

**Issue:** `pollPlaybackState` captures `handle` with `guard let handle = manzoHandle`, then immediately passes it to `manzo_close(handle)` and sets `manzoHandle = nil`. So far so good. But the method is called by a repeating `Timer`, and `Timer` does not guarantee single-shot execution even after `invalidate()` is called if it fires concurrently with the invalidate (the timer runs on the main run loop, but `invalidate()` from inside the timer callback is safe). The real problem is subtler: at line 196, after `manzo_close(handle)` and `manzoHandle = nil`, the captured `handle` raw pointer is now a freed Rust Arc. The code then calls `playlistManager.next()` which may return `nil`, and in that branch it calls `spectrumView?.stopRenderLoop()`. If `spectrumView` still holds `manzoHandle` from a previous frame (it was nilled at line 195 but the render loop fires on CADisplayLink which runs on the main thread — but the nil assignment and CADisplayLink callback are both main-thread so this is safe). The actual dangerous path is: if `manzo_close` is async inside Rust (it is not according to the Phase 2 spec, but worth documenting) the pointer is freed before the function returns. **More concretely:** in `applicationDidFinishLaunching` at line 59–64, `manzoHandle` is set and `spectrumView.manzoHandle = manzoHandle` (the Optional value). Then at line 195 `spectrumView?.manzoHandle = nil` runs. But there is a window between `manzo_close(handle)` at line 196 and the spectrumView nil assignment at line 195 — the order is: nil spectrum (195), close (196), nil handle (197). This is the correct order. However, after close at line 196, `handle` (the local binding) remains a dangling pointer for the remainder of the function scope. If any future code path in this function (or a future edit) reads `handle` after line 196, it would be a use-after-free. This is a latent structural issue that has already caused the Phase 3 `manzo_stop`-before-close ordering requirement.

**Fix:** Restructure so `handle` goes out of scope immediately after `manzo_close`, using a helper or explicit scope:

```swift
// In pollPlaybackState, replace:
spectrumView?.manzoHandle = nil
manzo_close(handle)
manzoHandle = nil

// With a do-scope to make the free boundary explicit and prevent future accidental reads:
spectrumView?.manzoHandle = nil
do {
    manzo_close(handle)
} // `handle` is not accessible after this comment but Swift does not enforce it
manzoHandle = nil
// Do NOT reference `handle` below this point.
```

More robustly, extract the close sequence into a private helper that takes the pointer by value, zeroes the instance var, and makes it impossible to reference the freed pointer afterward:

```swift
private func closeCurrentHandle() {
    guard let h = manzoHandle else { return }
    spectrumView?.manzoHandle = nil
    manzoHandle = nil        // nil the ivar BEFORE calling close
    manzo_close(h)           // h is a local copy; ivar already nil
}
```

This pattern eliminates the dangling binding entirely and is consistent across all three call sites (pollPlaybackState, jumpToTrack, removeTrackAt).

---

### CR-02: Force-unwrap `manzoWindow!` in `openFilePicker` — guaranteed crash path

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:364`

**Issue:** `op.beginSheetModal(for: manzoWindow!)` force-unwraps `manzoWindow`, which is an Optional set in `applicationDidFinishLaunching`. If `openFilePicker` is ever called before that method completes (e.g., via the `+` button being wired before `playlistPanel` is attached, or via a menu shortcut that fires before setup finishes), or if `manzoWindow` is released for any reason, this is a guaranteed crash with no recovery. `NSOpenPanel` requires a parent window for sheet presentation, so `nil` is not a valid fallback — but the crash should be handled gracefully.

**Fix:**
```swift
func openFilePicker() {
    guard let parentWindow = manzoWindow else {
        NSLog("MANZO Phase 8: openFilePicker — manzoWindow not available, aborting")
        return
    }
    let op = NSOpenPanel()
    // ... configure op ...
    op.beginSheetModal(for: parentWindow) { [weak self] response in
        // ...
    }
}
```

---

## Warnings

### WR-01: `currentIndex` is not persisted — playback position lost on every relaunch

**File:** `ManzoApp/ManzoApp/PlaylistManager.swift:112–133`

**Issue:** `save()` encodes only `tracks: [PlaylistTrack]`. `currentIndex` is never written to JSON. On relaunch, `load()` restores the track list correctly but `currentIndex` is reset to 0. The clamp at line 131 (`if currentIndex >= tracks.count`) operates on the freshly-initialized value of 0, never the persisted one. This means every relaunch begins from track 1 regardless of where the user was. This contradicts D-09 (JSON persistence across relaunch) if the intent is to restore playback position.

**Fix:** Either persist `currentIndex` alongside tracks, or document explicitly that position is intentionally not restored. If persisting:

```swift
private struct PlaylistState: Codable {
    var tracks: [PlaylistTrack]
    var currentIndex: Int
}

func save() {
    let state = PlaylistState(tracks: tracks, currentIndex: currentIndex)
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: playlistURL, options: .atomic)
}

func load() {
    guard let data  = try? Data(contentsOf: playlistURL),
          let state = try? JSONDecoder().decode(PlaylistState.self, from: data)
    else { return }
    tracks = state.tracks
    currentIndex = min(state.currentIndex, max(0, tracks.count - 1))
}
```

---

### WR-02: `pollPlaybackState` stops on missing file instead of skipping to next

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:210–215`

**Issue:** When `playlistManager.next()` returns a track whose file no longer exists on disk, `pollPlaybackState` invalidates the poll timer and stops the render loop entirely (lines 211–215). The user's playlist stops advancing permanently even if subsequent tracks are present and available. A single missing file should be skipped, not treated as end-of-playlist.

**Fix:** Replace the early return with a recursive advance:

```swift
guard FileManager.default.fileExists(atPath: nextPath) else {
    NSLog("MANZO Phase 8: next track missing at \(nextPath) — skipping")
    // Advance again: call pollPlaybackState-equivalent logic or loop
    // Simplest: schedule a recursive call on the next run loop turn
    DispatchQueue.main.async { [weak self] in self?.advanceToNextAvailableTrack() }
    return
}
```

---

### WR-03: `removeTrackAt` — empty-playlist edge case after removing the playing track

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:552–556`

**Issue:** When the playing track is removed and it was the last track (`tracks.count` is now 0), `playlistManager.remove(at:)` sets `currentIndex = max(0, 0-1)` = 0. Then `removeTrackAt` at line 554 calls `playlistManager.trackAt(playlistManager.currentIndex)` which is `trackAt(0)` on an empty array — this returns `nil` correctly, so the else-branch stops playback. This path is actually safe, but the issue is that `wasCurrentTrack` is evaluated using the index *before* removal (line 546), then `remove()` is called (line 547), which may change `currentIndex`. If the removed index was the last element and also `currentIndex`, after removal `currentIndex` becomes `max(0, tracks.count - 1)` = 0 (for a 1-element list becoming empty). The `jumpToTrack(at: playlistManager.currentIndex)` call on line 556 then calls `jumpToTrack(at: 0)` on an empty playlist. `trackAt(0)` returns nil so `jumpToTrack` returns early — this is safe. However, the logic is fragile: the intent is to jump to the *next* track after removal, but `PlaylistManager.remove()` clamps `currentIndex` to `max(0, count-1)` which on a 2-track playlist removing track 1 (last) gives `currentIndex=0`, jumping back to the beginning. This may be intentional but is not documented.

**Fix:** Document the wrap-around behavior explicitly, or check `tracks.isEmpty` before calling `jumpToTrack`:

```swift
if wasCurrentTrack {
    if playlistManager.tracks.isEmpty {
        // Stop playback entirely.
        if let handle = manzoHandle {
            spectrumView?.manzoHandle = nil
            manzoHandle = nil
            manzo_close(handle)
            spectrumView?.stopRenderLoop()
        }
        pollTimer?.invalidate()
        pollTimer = nil
    } else if let nextTrack = playlistManager.trackAt(playlistManager.currentIndex),
              FileManager.default.fileExists(atPath: nextTrack.path) {
        jumpToTrack(at: playlistManager.currentIndex)
    } else {
        // Stop — next track is also missing.
        // ... stop playback ...
    }
}
```

---

### WR-04: Marquee skip-guard casts `NSNumber` to `CGFloat` unsafely — may silently fail on reuse

**File:** `ManzoApp/ManzoApp/PlaylistRowView.swift:121–122`

**Issue:** The skip-if-running guard at line 121–122 reads:

```swift
if let existing = trackLabel.layer?.animation(forKey: "marquee") as? CAKeyframeAnimation,
   abs((existing.values?.last as? CGFloat ?? 0) - (-overflow)) < 1 { return }
```

`CAKeyframeAnimation.values` stores elements typed as `Any`. For `transform.translation.x` animations set with `CGFloat` values on macOS, Core Animation boxes them as `NSNumber`, not `CGFloat`. The cast `as? CGFloat` will **always fail** on macOS (CGFloat is not a class type bridged via `as?` from `Any` when stored in the CA values array — it is stored as `NSNumber`). This means the guard condition always evaluates `(0 - (-overflow)) < 1`, i.e., it only skips when `overflow < 1`. For any real overflow, the guard falls through, removes the existing animation, and recreates it from scratch on every `layout()` call — including every frame during a window resize. This causes animation restarts on every layout pass for the active track, making the marquee stutter visibly during resize.

**Fix:**
```swift
if let existing = trackLabel.layer?.animation(forKey: "marquee") as? CAKeyframeAnimation,
   let lastVal = existing.values?.last as? NSNumber,
   abs(CGFloat(lastVal.doubleValue) - (-overflow)) < 1 { return }
```

---

### WR-05: `acceptDrop` calls `moveRow` then immediately `reloadData` — animation flash

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:477–481`

**Issue:** `tableView.moveRow(at:to:)` triggers NSTableView's built-in smooth row-move animation. Immediately calling `tableView.reloadData()` on the very next line (line 481) cancels the in-flight animation and reloads all rows, producing a visible flash. These two calls are contradictory: `moveRow` is for visual smoothness; `reloadData` nukes it.

**Fix:** Remove the `moveRow` call and rely solely on `reloadData`, or remove `reloadData` and instead reload only the affected rows after the move animation completes. The simplest correct fix:

```swift
// Remove tableView.moveRow call. Use reloadData only:
playlistManager.move(from: sourceRow, to: row)
tableView.reloadData()
playlistPanel?.updateTrackCount(playlistManager.tracks.count)
```

If smooth animation is desired, use `beginUpdates`/`endUpdates` with `moveRow` and no `reloadData`.

---

## Info

### IN-01: `playlistURL` computed property recreates directory on every access

**File:** `ManzoApp/ManzoApp/PlaylistManager.swift:138–143`

**Issue:** `playlistURL` is a computed `var` that calls `FileManager.default.createDirectory` on every invocation. It is called from `save()` and `load()`, so the directory creation call fires at minimum twice per mutation. The `withIntermediateDirectories: true` flag makes this idempotent and safe, but it is unnecessary overhead. The `try?` suppresses errors silently; if the directory cannot be created (e.g., sandbox denial), `save()` will silently fail.

**Fix:** Create the directory once in `init()` and store `playlistURL` as a `let` constant.

---

### IN-02: `selectionLayer` inserted at index 0 in `ManzoPlaylistRowBackground` — may be occluded

**File:** `ManzoApp/ManzoApp/PlaylistRowView.swift:222`

**Issue:** `layer?.addSublayer(selectionLayer)` appends the selection layer at the top of the NSTableRowView's sublayer stack. NSTableView adds cell views (`PlaylistRowView`) as subviews of the row view, and subviews composite above sublayers. This means the selection highlight is already behind all cell content, which is the intended behavior per the comment at line 208–210. No bug here — but the comment says the layer is used *instead* of `drawSelection()` because drawSelection is "occluded by cell view layers." This is correct reasoning. However, if `wantsLayer = true` is set on the row view (line 215) and cell views also have `wantsLayer = true`, the layer tree compositing order means the selection layer at index 0 of the row's layer will render behind all cell layers. The `cornerRadius = 3` on `selectionLayer` with the `bounds.insetBy(dx:2, dy:1)` frame is correct. No action needed, but add a comment confirming intentional z-order.

---

### IN-03: `stopMarquee` resets `transform` but `startMarquee` uses `transform.translation.x` keyPath — ordering risk

**File:** `ManzoApp/ManzoApp/PlaylistRowView.swift:143–149`

**Issue:** `stopMarquee` sets `trackLabel.layer?.transform = CATransform3DIdentity`. If the layer has any other transform applied (e.g., from a superclass or future addition), this wipes it. Using `setValue(0, forKeyPath: "transform.translation.x")` would be more surgical.

**Fix:**
```swift
private func stopMarquee() {
    guard trackLabel.layer?.animation(forKey: "marquee") != nil else { return }
    trackLabel.layer?.removeAnimation(forKey: "marquee")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    trackLabel.layer?.setValue(0.0, forKeyPath: "transform.translation.x")
    CATransaction.commit()
}
```

---

### IN-04: `applicationSupportDirectory` force-unwrap in `playlistURL`

**File:** `ManzoApp/ManzoApp/PlaylistManager.swift:139`

**Issue:** `FileManager.default.urls(for:in:).first!` force-unwraps the application support directory URL. On a standard macOS install this never returns an empty array, but it is a force-unwrap on a computed property called on every save/load cycle. If it were ever nil (sandboxing edge case, unit test environment), it would crash silently in the background queue.

**Fix:**
```swift
private var playlistURL: URL {
    guard let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
        NSLog("MANZO: applicationSupportDirectory unavailable — playlist persistence disabled")
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manzo-playlist.json")
    }
    // ...
}
```

---

_Reviewed: 2026-04-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
