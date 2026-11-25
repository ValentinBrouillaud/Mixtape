import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-only publisher. No player, authentication or audio download code runs in widgets.
@MainActor
final class WidgetSnapshotBridge {
    static let shared = WidgetSnapshotBridge()
    private var snapshot = MixtapeWidgetStorage.load()
    private var playlistArtworkCandidates: [String: [String]] = [:]
    private let writeQueue = DispatchQueue(label: "com.alexcding.mixtape.widget-snapshot")

    func updatePlayback(song: Song?, isPlaying: Bool) {
        let current = song.map {
            MixtapeWidgetSong(
                videoId: $0.videoId, title: $0.title, artist: $0.artistsDisplay,
                artworkFileName: snapshot.currentSong?.videoId == $0.videoId ? snapshot.currentSong?.artworkFileName : nil
            )
        }
        let retainedCurrent = current ?? snapshot.currentSong
        guard retainedCurrent != snapshot.currentSong || snapshot.isPlaying != isPlaying else { return }
        snapshot.currentSong = retainedCurrent
        snapshot.isPlaying = isPlaying
        publish()
    }

    func updateHistory(_ entries: [ListeningHistoryEntry]) {
        snapshot.recentSongs = entries.prefix(100).map {
            MixtapeWidgetSong(videoId: $0.videoId, title: $0.title, artist: $0.artist)
        }
        publish()
    }

    func updatePlaylists(_ playlists: [MixtapeQuickPlaylist]) {
        playlistArtworkCandidates = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id.uuidString, Array($0.songs.prefix(4).map(\.videoId))) })
        snapshot.playlists = playlists.map {
            MixtapeWidgetPlaylist(id: $0.id.uuidString, title: $0.name, songCount: $0.songs.count)
        }
        publish()
    }

    func refreshArtwork() { publish() }

    private func publish() {
        guard let root = MixtapeWidgetStorage.containerURL else { return }
        var sources: [String: URL] = [:]
        func withArtwork(_ song: MixtapeWidgetSong) -> MixtapeWidgetSong {
            var result = song
            result.artworkFileName = nil
            if let url = HistoryArtworkCache.shared.cachedFileURL(videoId: song.videoId) {
                result.artworkFileName = url.lastPathComponent
                sources[url.lastPathComponent] = url
            }
            return result
        }
        snapshot.currentSong = snapshot.currentSong.map(withArtwork)
        snapshot.recentSongs = snapshot.recentSongs.map(withArtwork)
        snapshot.playlists = snapshot.playlists.map { playlist in
            var result = playlist
            result.artworkFileName = nil
            if let source = (playlistArtworkCandidates[playlist.id] ?? []).compactMap({ HistoryArtworkCache.shared.cachedFileURL(videoId: $0) }).first {
                result.artworkFileName = source.lastPathComponent
                sources[source.lastPathComponent] = source
            }
            return result
        }
        snapshot.updatedAt = Date()
        let pending = snapshot
        let sourceFiles = sources
        writeQueue.async {
            do {
                let artworkDirectory = root.appendingPathComponent("Artwork", isDirectory: true)
                try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
                for (fileName, source) in sourceFiles {
                    let target = artworkDirectory.appendingPathComponent(fileName)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try? FileManager.default.copyItem(at: source, to: target)
                    }
                }
                let data = try JSONEncoder().encode(pending)
                try data.write(to: root.appendingPathComponent(MixtapeWidgetStorage.snapshotFileName), options: .atomic)
                let retained = Set(sourceFiles.keys)
                for existing in (try? FileManager.default.contentsOfDirectory(at: artworkDirectory, includingPropertiesForKeys: nil)) ?? [] {
                    if !retained.contains(existing.lastPathComponent) { try? FileManager.default.removeItem(at: existing) }
                }
                #if canImport(WidgetKit)
                Task { @MainActor in WidgetCenter.shared.reloadAllTimelines() }
                #endif
            } catch {
                DiagnosticsLogger.ui.error("Unable to publish widget metadata: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
@Observable
final class WidgetNavigationRouter {
    static let shared = WidgetNavigationRouter()
    var pendingPlaylistID: UUID?
}
