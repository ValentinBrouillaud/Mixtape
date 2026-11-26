import Foundation
import Observation
import os

/// A device-local list of the last 100 distinct songs actually heard.
/// Recording history never queues an audio download or requests playback.
@MainActor
@Observable
final class ListeningHistoryStore {
    static let shared = ListeningHistoryStore()

    private(set) var entries: [ListeningHistoryEntry] = []
    @ObservationIgnored private var currentSong: Song?
    @ObservationIgnored private var progressGate = ListeningProgressGate()
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "com.alexcding.mixtape.listening-history")

    convenience init() {
        self.init(fileURL: Self.defaultFileURL)
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
        defer {
            HistoryArtworkCache.shared.retain(entries: entries)
            WidgetSnapshotBridge.shared.updateHistory(entries)
        }
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            entries = ListeningHistoryPolicy.normalized(try JSONDecoder().decode(
                [ListeningHistoryEntry].self, from: Data(contentsOf: fileURL)
            ))
        } catch {
            DiagnosticsLogger.ui.error("Unable to read listening history: \(error.localizedDescription)")
        }
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Mixtape", isDirectory: true)
            .appendingPathComponent("listening-history.json")
    }

    /// Starting a track does not record a listen. Only advancing playback can do that.
    func beginPlaybackSession(for song: Song) {
        currentSong = song
        progressGate = ListeningProgressGate()
    }

    func endPlaybackSession() {
        currentSong = nil
        progressGate = ListeningProgressGate()
    }

    /// Feed only callbacks belonging to the active player and current playback occurrence.
    func observePlayback(isPlaying: Bool, position: TimeInterval) {
        guard let currentSong,
              progressGate.observe(isPlaying: isPlaying, position: position, uptime: ProcessInfo.processInfo.systemUptime)
        else { return }
        entries = ListeningHistoryPolicy.recording(Self.entry(for: currentSong, at: Date()), in: entries)
        save()
    }

    /// Direct-video playback may receive its title/artwork after playback has started.
    func updateCurrentSong(_ song: Song) {
        guard currentSong?.videoId == song.videoId else { return }
        currentSong = song
        guard progressGate.hasQualified,
              let index = entries.firstIndex(where: { $0.videoId == song.videoId }) else { return }
        entries[index] = Self.entry(for: song, at: entries[index].lastPlayedAt)
        save()
    }

    func remove(videoId: String) {
        entries.removeAll { $0.videoId == videoId }
        save()
    }

    func clear() {
        entries.removeAll()
        // An already qualified session stays qualified, so the next timer tick
        // cannot silently put a just-cleared song back in the list.
        save()
    }

    private static func entry(for song: Song, at date: Date) -> ListeningHistoryEntry {
        ListeningHistoryEntry(
            videoId: song.videoId, title: song.title, artist: song.artistsDisplay,
            artworkURL: song.thumbnailURL,
            duration: song.duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            lastPlayedAt: date,
            artistCredits: song.artists.map { ListeningHistoryArtist(id: $0.id, name: $0.name) }
        )
    }

    private func save() {
        HistoryArtworkCache.shared.retain(entries: entries)
        WidgetSnapshotBridge.shared.updateHistory(entries)
        guard let fileURL else { return }
        do {
            // Encode on the main actor; ordered writes prevent an older receipt
            // from resurrecting removed entries or replacing newer listens.
            let data = try JSONEncoder().encode(entries)
            let logger = DiagnosticsLogger.ui
            writeQueue.async {
                do {
                    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    logger.error("Unable to save listening history: \(error.localizedDescription)")
                }
            }
        } catch {
            DiagnosticsLogger.ui.error("Unable to encode listening history: \(error.localizedDescription)")
        }
    }
}

extension ListeningHistoryEntry {
    /// Reconstruct only the metadata needed for an explicit user-requested replay.
    @MainActor var playbackSong: Song {
        let knownArtists = (artistCredits ?? []).map { Artist(id: $0.id, name: $0.name) }
        return Song(
            id: videoId, title: title,
            artists: knownArtists.isEmpty && !artist.isEmpty ? [Artist(id: "", name: artist)] : knownArtists,
            duration: duration, thumbnailURL: artworkURL, videoId: videoId
        )
    }
}
