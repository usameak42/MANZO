import Foundation
import AVFoundation

// PlaylistManager — owned by AppDelegate, replaces Phase 3 trackQueue + currentTrackIndex (D-12).
// All mutations call save() automatically (D-11: autosave after every mutation).
// Thread model: all public methods called on main thread; add(urls:) dispatches internally to background.
final class PlaylistManager {

    // MARK: - Public State

    var tracks: [PlaylistTrack] = []
    var currentIndex: Int = 0

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - CRUD

    /// Add audio files by URL. Reads AVFoundation metadata (artist, title, duration) on a
    /// background queue (D-07). Appends to tracks and saves on main queue when done.
    /// Caller should reload the NSTableView in the completion block passed via onAdded closure.
    func add(urls: [URL], onAdded: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var newTracks: [PlaylistTrack] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                var artist:   String? = nil
                var title:    String? = nil
                var duration: Double  = 0

                // Synchronous metadata load — acceptable on background queue (D-07).
                // AVURLAsset.duration may block; .commonMetadata is synchronous on disk files.
                let rawDuration = asset.duration.seconds
                duration = rawDuration.isNaN || rawDuration < 0 ? 0 : rawDuration
                for item in asset.commonMetadata {
                    if item.commonKey == .commonKeyArtist, let v = item.stringValue { artist = v }
                    if item.commonKey == .commonKeyTitle,  let v = item.stringValue { title  = v }
                }
                let track = PlaylistTrack(path: url.path, artist: artist, title: title, duration: duration)
                newTracks.append(track)
                NSLog("MANZO Phase 8: PlaylistManager.add — loaded %@ (%@)", url.lastPathComponent, track.formattedDuration)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tracks.append(contentsOf: newTracks)
                self.save()
                NSLog("MANZO Phase 8: PlaylistManager.add — appended %d tracks, total=%d", newTracks.count, self.tracks.count)
                onAdded?()
            }
        }
    }

    /// Remove track at index. Updates currentIndex if needed (D-13).
    /// If removed track is currently playing: caller is responsible for advancing playback.
    func remove(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        // Adjust currentIndex to remain valid after removal.
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex, currentIndex >= tracks.count {
            currentIndex = max(0, tracks.count - 1)
        }
        save()
        NSLog("MANZO Phase 8: PlaylistManager.remove — removed index=%d, currentIndex=%d, total=%d", index, currentIndex, tracks.count)
    }

    /// Reorder track. Move semantics: element at `from` is inserted before the element at `to`. (D-11)
    func move(from: Int, to: Int) {
        guard from >= 0, from < tracks.count,
              to   >= 0, to   <= tracks.count,
              from != to else { return }
        let track = tracks.remove(at: from)
        let insertAt = to > from ? to - 1 : to
        tracks.insert(track, at: insertAt)
        // Keep currentIndex tracking the same logical track after the move.
        if currentIndex == from {
            currentIndex = insertAt
        } else if from < currentIndex, to > currentIndex {
            currentIndex -= 1
        } else if from > currentIndex, to <= currentIndex {
            currentIndex += 1
        }
        save()
        NSLog("MANZO Phase 8: PlaylistManager.move — from=%d to=%d, currentIndex=%d", from, to, currentIndex)
    }

    /// Advance to next track. Returns next PlaylistTrack or nil if exhausted. (D-15)
    func next() -> PlaylistTrack? {
        let nextIndex = currentIndex + 1
        guard nextIndex < tracks.count else {
            NSLog("MANZO Phase 8: PlaylistManager.next — playlist exhausted at index=%d", currentIndex)
            return nil
        }
        currentIndex = nextIndex
        NSLog("MANZO Phase 8: PlaylistManager.next — advanced to index=%d, path=%@", currentIndex, tracks[currentIndex].path)
        return tracks[currentIndex]
    }

    /// Returns track at index, or nil if out of range.
    func trackAt(_ index: Int) -> PlaylistTrack? {
        guard index >= 0, index < tracks.count else { return nil }
        return tracks[index]
    }

    // MARK: - Persistence (D-09, D-11)

    /// Atomic JSON write to ~/Library/Application Support/Manzo/playlist.json.
    func save() {
        guard let data = try? JSONEncoder().encode(tracks) else {
            NSLog("MANZO Phase 8: PlaylistManager.save — encode failed (unexpected)")
            return
        }
        try? data.write(to: playlistURL, options: .atomic)
        NSLog("MANZO Phase 8: PlaylistManager.save — %d tracks written to %@", tracks.count, playlistURL.path)
    }

    /// Load from JSON. Silently starts with empty list if file missing or corrupt.
    func load() {
        guard let data  = try? Data(contentsOf: playlistURL),
              let list  = try? JSONDecoder().decode([PlaylistTrack].self, from: data)
        else {
            NSLog("MANZO Phase 8: PlaylistManager.load — no playlist found, starting empty")
            return
        }
        tracks = list
        // Clamp currentIndex in case JSON was written with a larger index.
        if currentIndex >= tracks.count { currentIndex = max(0, tracks.count - 1) }
        NSLog("MANZO Phase 8: PlaylistManager.load — loaded %d tracks from %@", tracks.count, playlistURL.path)
    }

    // MARK: - Private

    /// ~/Library/Application Support/Manzo/playlist.json (D-09).
    private var playlistURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Manzo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("playlist.json")
    }
}
