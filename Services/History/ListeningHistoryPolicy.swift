import Foundation

/// A local listening receipt. It contains display metadata, never stream URLs or audio.
nonisolated struct ListeningHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let videoId: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let duration: TimeInterval?
    let lastPlayedAt: Date
    var artistCredits: [ListeningHistoryArtist]? = nil

    var id: String { videoId }
}

nonisolated struct ListeningHistoryArtist: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

nonisolated enum ListeningHistoryPolicy {
    static let capacity = 100

    /// Receipts are stored newest-first. Preserve that order even after a clock change.
    static func normalized(_ entries: [ListeningHistoryEntry]) -> [ListeningHistoryEntry] {
        var seen: Set<String> = []
        return entries
            .filter { !$0.videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.videoId).inserted }
            .prefix(capacity)
            .map { $0 }
    }

    static func recording(_ entry: ListeningHistoryEntry, in entries: [ListeningHistoryEntry]) -> [ListeningHistoryEntry] {
        // A new listen belongs at the front even when the device clock was adjusted.
        guard !entry.videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return normalized(entries) }
        let rest = normalized(entries).filter { $0.videoId != entry.videoId }
        return [entry] + Array(rest.prefix(capacity - 1))
    }
}

/// Counts real advancing playback, excluding loading, pauses, stalls and large seeks.
/// The player creates a fresh gate for every playback occurrence, including repeat-one.
nonisolated struct ListeningProgressGate: Sendable {
    static let requiredListeningTime: TimeInterval = 5
    private(set) var listenedTime: TimeInterval = 0
    private(set) var hasQualified = false
    private var lastPosition: TimeInterval?
    private var lastUptime: TimeInterval?

    /// Returns true exactly once, when at least five seconds have actually advanced.
    mutating func observe(isPlaying: Bool, position: TimeInterval, uptime: TimeInterval) -> Bool {
        guard !hasQualified else { return false }
        guard isPlaying, position.isFinite, position >= 0, uptime.isFinite, uptime >= 0 else {
            suspend()
            return false
        }
        guard let previousPosition = lastPosition, let previousUptime = lastUptime else {
            lastPosition = position
            lastUptime = uptime
            return false
        }
        let elapsed = uptime - previousUptime
        let advanced = position - previousPosition
        guard elapsed > 0 else { return false }
        // Duplicate timer callbacks do not steal time from the next advancing sample.
        if advanced == 0, elapsed <= 10 { return false }
        lastPosition = position
        lastUptime = uptime
        guard elapsed <= 10, advanced > 0,
              advanced <= elapsed + max(0.5, elapsed * 0.5) else { return false }
        listenedTime += min(advanced, elapsed)
        guard listenedTime + 0.000_001 >= Self.requiredListeningTime else { return false }
        hasQualified = true
        return true
    }

    mutating func suspend() {
        lastPosition = nil
        lastUptime = nil
    }
}
