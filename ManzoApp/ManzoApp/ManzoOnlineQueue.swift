//
//  ManzoOnlineQueue.swift
//  MANZO — Online queue model for the ONLINE tab in ManzoPlaylistPanel.
//
//  Drop-in, dependency-free. Holds the queue, the active source filter, and a
//  stubbed adapter protocol for resolving a YouTube/SoundCloud URL into a
//  playable track. No real network calls — `MockOnlineSourceAdapter` returns
//  fabricated metadata after a short delay so the panel can be exercised
//  end-to-end.
//
//  Wire-up (AppDelegate side):
//      let queue = ManzoOnlineQueue()
//      queue.adapter = MockOnlineSourceAdapter()      // swap for real later
//      panel.onlineQueue = queue                       // ManzoPlaylistPanel
//
//  Visual reference: playlist-online-explorations.html — variation A.
//
import Foundation

// MARK: - Source --------------------------------------------------------------

public enum OnlineSource: String, CaseIterable, Codable {
    case youtube    = "yt"
    case soundcloud = "sc"

    public var badge: String {
        switch self {
        case .youtube:    return "YT"
        case .soundcloud: return "SC"
        }
    }
    public var displayName: String {
        switch self {
        case .youtube:    return "YouTube"
        case .soundcloud: return "SoundCloud"
        }
    }
}

public enum OnlineSourceFilter: Equatable {
    case all
    case only(OnlineSource)
}

// MARK: - Track ---------------------------------------------------------------

public struct OnlineTrack: Identifiable, Equatable {
    public let id: UUID
    public var source:   OnlineSource
    public var title:    String
    public var url:      URL
    public var duration: TimeInterval   // <0 / .nan / .infinity → unknown or live
    public var isLive:   Bool

    public init(id: UUID = UUID(),
                source: OnlineSource,
                title: String,
                url: URL,
                duration: TimeInterval,
                isLive: Bool = false) {
        self.id = id
        self.source = source
        self.title = title
        self.url = url
        self.duration = duration
        self.isLive = isLive
    }

    /// "M:SS" — or "LIVE" for live streams; "−:−−" for unknown.
    public var durationString: String {
        if isLive { return "LIVE" }
        if duration.isNaN || duration.isInfinite || duration < 0 { return "−:−−" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Adapter -------------------------------------------------------------

/// Resolves a URL into an `OnlineTrack`. Real adapters do network work; the
/// mock fabricates plausible data after 600ms. The panel calls this during
/// `addURL(_:)` and shows the validating/error/success states based on the
/// completion result.
public protocol OnlineSourceAdapter {
    /// Returns the source for a URL, or nil if unsupported.
    func detect(url: URL) -> OnlineSource?

    /// Resolve metadata. Completion is invoked on the main queue.
    func resolve(url: URL,
                 completion: @escaping (Result<OnlineTrack, OnlineQueueError>) -> Void)
}

public enum OnlineQueueError: Error, LocalizedError {
    case unsupportedURL
    case malformedURL
    case networkUnavailable
    case ageRestricted
    case privateOrUnavailable
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL:      return "Only YouTube and SoundCloud URLs are supported."
        case .malformedURL:        return "That doesn’t look like a valid URL."
        case .networkUnavailable:  return "No network."
        case .ageRestricted:       return "Track is age-restricted."
        case .privateOrUnavailable:return "Track is private or unavailable."
        case .unknown(let m):      return m
        }
    }
}

// MARK: - Mock adapter --------------------------------------------------------

/// Stub: pretends to resolve a URL after 600ms with fabricated metadata.
/// Replace with `YTSourceAdapter` / `SCSourceAdapter` later — same protocol.
public final class MockOnlineSourceAdapter: OnlineSourceAdapter {

    public init() {}

    public func detect(url: URL) -> OnlineSource? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("youtu.be") || host.contains("youtube.com") { return .youtube }
        if host.contains("soundcloud.com") { return .soundcloud }
        return nil
    }

    public func resolve(url: URL,
                        completion: @escaping (Result<OnlineTrack, OnlineQueueError>) -> Void) {
        guard let src = detect(url: url) else {
            DispatchQueue.main.async { completion(.failure(.unsupportedURL)) }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // 5% live-stream chance to exercise the LIVE row treatment.
            let isLive = src == .youtube && Bool.random() && Bool.random() && Bool.random()
            let dur: TimeInterval = isLive ? .infinity
                                           : TimeInterval(Int.random(in: 90...600))
            let title: String = {
                let stem = url.lastPathComponent.isEmpty ? url.host ?? "track" : url.lastPathComponent
                return "[\(src.badge)] \(stem)"
            }()
            completion(.success(OnlineTrack(source: src, title: title, url: url,
                                            duration: dur, isLive: isLive)))
        }
    }
}

// MARK: - Queue ---------------------------------------------------------------

public final class ManzoOnlineQueue {

    // Adapter is swappable; defaults to the mock so the panel works out of the box.
    public var adapter: OnlineSourceAdapter = MockOnlineSourceAdapter()

    // Storage --------------------------------------------------------------
    public private(set) var tracks: [OnlineTrack] = []
    public private(set) var currentIndex: Int = -1
    public var filter: OnlineSourceFilter = .all { didSet { onChange?() } }

    // Observers ------------------------------------------------------------
    /// Fired on any tracks/currentIndex/filter mutation. UI re-renders here.
    public var onChange: (() -> Void)?
    /// Fired when the user picks a row to play.
    public var onPlay: ((OnlineTrack) -> Void)?

    public init() {}

    // Filtered view --------------------------------------------------------
    public var filteredTracks: [(index: Int, track: OnlineTrack)] {
        tracks.enumerated().compactMap { (i, t) in
            switch filter {
            case .all:                              return (i, t)
            case .only(let s) where s == t.source:  return (i, t)
            default:                                return nil
            }
        }
    }

    public var youtubeCount:    Int { tracks.filter { $0.source == .youtube    }.count }
    public var soundcloudCount: Int { tracks.filter { $0.source == .soundcloud }.count }
    public var liveCount:       Int { tracks.filter(\.isLive).count }
    public var totalSeconds:    TimeInterval {
        tracks.reduce(0) { $0 + (($1.isLive || $1.duration.isNaN || $1.duration.isInfinite || $1.duration < 0) ? 0 : $1.duration) }
    }

    // Mutation --------------------------------------------------------------

    /// Resolve a URL string and append on success. Reports state via callback
    /// so the URL bar can show validating → error/success.
    public enum AddState { case validating, success(OnlineTrack), failure(OnlineQueueError) }

    public func addURL(_ raw: String,
                       state: @escaping (AddState) -> Void) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        else { state(.failure(.malformedURL)); return }

        state(.validating)
        adapter.resolve(url: url) { [weak self] result in
            switch result {
            case .success(let track):
                self?.tracks.append(track)
                self?.onChange?()
                state(.success(track))
            case .failure(let err):
                state(.failure(err))
            }
        }
    }

    public func remove(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        tracks.remove(at: index)
        if currentIndex == index            { currentIndex = -1 }
        else if currentIndex > index        { currentIndex -= 1 }
        onChange?()
    }

    public func clearAll() {
        guard !tracks.isEmpty else { return }
        tracks.removeAll()
        currentIndex = -1
        onChange?()
    }

    public func play(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
        onChange?()
        onPlay?(tracks[index])
    }

    /// For tests / seeding from disk.
    public func setTracks(_ newTracks: [OnlineTrack], currentIndex: Int = -1) {
        self.tracks = newTracks
        self.currentIndex = currentIndex
        onChange?()
    }
}
