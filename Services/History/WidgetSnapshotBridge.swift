import Foundation
import Observation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-only publisher. No player, authentication or audio download code runs in widgets.
@MainActor
@Observable
final class WidgetSnapshotBridge {
    static let shared = WidgetSnapshotBridge()
    private(set) var lastPublishedAt: Date?
    private(set) var publicationIssue: MixtapeWidgetReadIssue?
    private(set) var lastPublishedTitle: String?
    private(set) var lastPublishedPlaylistCount = 0
    private(set) var lastPublishedSharedIdentifier: String?
    private(set) var publicationDetails: String?
    private var snapshot = MixtapeWidgetStorage.load()
    private var publicationGeneration = 0
    private var playlistArtworkCandidates: [String: [String]] = [:]
    private let writeQueue = DispatchQueue(label: "com.alexcding.mixtape.widget-snapshot")

    func updatePlayback(song: Song?, isPlaying: Bool, position: TimeInterval? = nil,
                        duration: TimeInterval? = nil, isAdvancing: Bool? = nil, force: Bool = false) {
        let current = song.map {
            MixtapeWidgetSong(
                videoId: $0.videoId, title: $0.title, artist: $0.artistsDisplay,
                artworkFileName: snapshot.currentSong?.videoId == $0.videoId ? snapshot.currentSong?.artworkFileName : nil
            )
        }
        let retainedCurrent = current ?? snapshot.currentSong
        let now = Date()
        let playback = retainedCurrent.map { current in
            let sameTrack = snapshot.playback?.videoID == current.videoId
            let fallbackPosition = sameTrack ? snapshot.playback?.position(at: now) ?? 0 : 0
            let knownDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                ?? song?.duration ?? (sameTrack ? snapshot.playback?.duration : nil)
            return MixtapeWidgetPlayback(videoID: current.videoId, position: position ?? fallbackPosition,
                duration: knownDuration, sampledAt: now, isAdvancing: isAdvancing ?? isPlaying)
        }
        let changedPosition = playback.map { $0.needsPublication(after: snapshot.playback) } ?? false
        guard force || retainedCurrent != snapshot.currentSong || snapshot.isPlaying != isPlaying || changedPosition else { return }
        snapshot.currentSong = retainedCurrent
        snapshot.isPlaying = isPlaying
        snapshot.playback = playback
        publish()
    }

    func updateAppearance(_ appearance: MixtapeAppearance) {
        guard snapshot.appearance != appearance.rawValue else { return }
        snapshot.appearance = appearance.rawValue
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

    /// Explicitly retry publication when returning to the app or diagnosing widgets.
    func refresh() { publish() }

    /// Make the latest snapshot visible before an audio App Intent completes.
    func flush() async {
        await withCheckedContinuation { continuation in
            writeQueue.async { continuation.resume() }
        }
    }

    private func publish() {
        publicationGeneration &+= 1
        let generation = publicationGeneration
        let root = MixtapeWidgetStorage.containerURL
        guard root != nil || !MixtapeWidgetKeychain.candidates(in: MixtapeWidgetStorage.environment).isEmpty else {
            publicationIssue = .sharedContainerUnavailable
            publicationDetails = "No accessible App Group or keychain identity"
            DiagnosticsLogger.ui.error("Widget publication unavailable: no accessible shared container")
            return
        }
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
                let sharedIdentifier: String
                if let root {
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
                    sharedIdentifier = MixtapeWidgetStorage.resolvedAppGroupIdentifier ?? MixtapeWidgetStorage.appGroup
                } else {
                    sharedIdentifier = try MixtapeWidgetKeychain.publish(pending, sources: sourceFiles)
                }
                #if canImport(WidgetKit)
                Task { @MainActor [weak self] in
                    WidgetCenter.shared.reloadAllTimelines()
                    guard let self, self.publicationGeneration == generation else { return }
                    self.lastPublishedAt = pending.updatedAt
                    self.lastPublishedTitle = pending.currentSong?.title ?? pending.recentSongs.first?.title
                    self.lastPublishedPlaylistCount = pending.playlists.count
                    self.lastPublishedSharedIdentifier = sharedIdentifier
                    self.publicationIssue = nil
                    self.publicationDetails = nil
                }
                #endif
            } catch {
                let details = error.localizedDescription
                DiagnosticsLogger.ui.error("Unable to publish widget metadata: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    guard let self, self.publicationGeneration == generation else { return }
                    self.publicationIssue = .unreadableSnapshot
                    self.publicationDetails = details
                }
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
