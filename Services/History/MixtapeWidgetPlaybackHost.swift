import FactoryKit
import Foundation
import WidgetKit

@MainActor
enum MixtapeWidgetPlaybackHost {
    static func perform(shouldPlay: Bool, videoID: String?, playlistID: String?) async throws {
        let player = Container.shared.playerManager()
        let action: MixtapeWidgetPlaybackAction = shouldPlay ? .play : .pause
        if action.shouldChange(isPlaying: player.isPlaying) {
            if shouldPlay {
                if player.currentTrack != nil || !player.queue.isEmpty {
                    await player.playPause()
                } else if let playlistID,
                          let playlist = MixtapeQuickPlaylists.shared.playlists.first(where: { $0.id.uuidString == playlistID }),
                          !playlist.songs.isEmpty {
                    await player.playQueue(playlist.songs)
                } else if let entry = ListeningHistoryStore.shared.entries.first(where: { $0.videoId == videoID })
                    ?? ListeningHistoryStore.shared.entries.first {
                    await player.play(song: entry.playbackSong)
                } else if let videoID, !videoID.isEmpty {
                    await player.play(videoId: videoID)
                }
            } else {
                await player.pause()
            }
        }
        let bridge = WidgetSnapshotBridge.shared
        bridge.updatePlayback(song: player.currentTrack, isPlaying: player.isPlaying,
            position: player.progress, duration: player.duration, force: true)
        await bridge.flush()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
