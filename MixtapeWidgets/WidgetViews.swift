import AppIntents
import Foundation
import ImageIO
import SwiftUI
import WidgetKit

enum WidgetStyle {
    static let red = MixtapePalette.accent
    static let background = MixtapePalette.background(.dark)
}

struct WidgetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    let appearance: String?
    @ViewBuilder var content: () -> Content
    private var scheme: ColorScheme {
        (MixtapeAppearance(rawValue: appearance ?? "") ?? .system).colorScheme ?? systemScheme
    }
    var body: some View {
        content()
            .environment(\.colorScheme, scheme)
            .tint(MixtapePalette.accent)
            .containerBackground(MixtapePalette.background(scheme), for: .widget)
    }
}

private struct WidgetArtwork: View {
    let fileName: String?
    let size: CGFloat
    var symbol = "music.note"
    var body: some View {
        Group {
            if let url = MixtapeWidgetStorage.artworkURL(fileName: fileName),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: Int(size * 3),
               ] as CFDictionary) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Color.primary.opacity(0.07).overlay {
                    Image(systemName: symbol).font(.system(size: size * 0.34, weight: .light))
                        .foregroundStyle(WidgetStyle.red)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .accessibilityHidden(true)
    }
}

private struct WidgetTrackCaption: View {
    let song: MixtapeWidgetSong?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let song {
                Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(song.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Open Mixtape", tableName: "WidgetStatus")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetPlaybackButton: View {
    let snapshot: MixtapeWidgetSnapshot
    var playlistID: String? = nil
    private var song: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }
    var body: some View {
        Button(intent: MixtapeWidgetPlaybackIntent(shouldPlay: !snapshot.isPlaying,
            videoID: song?.videoId, playlistID: playlistID)) {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(WidgetStyle.red, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(song == nil && playlistID == nil)
        .accessibilityLabel(Text(snapshot.isPlaying ? "Pause" : "Play", tableName: "MixtapeTheme"))
        .accessibilityHint(Text(song?.title ?? "Mixtape"))
    }
}

private struct WidgetPlaybackProgress: View {
    let snapshot: MixtapeWidgetSnapshot
    var body: some View {
        Group {
            if let playback = snapshot.playback, let range = playback.timerInterval {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: snapshot.playback?.fraction(at: Date()) ?? 0)
            }
        }
        .progressViewStyle(.linear)
        .tint(WidgetStyle.red)
        .frame(height: 3)
        .accessibilityLabel(Text("Playback position", tableName: "MixtapeTheme"))
    }
}

struct ResumeWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var song: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetArtwork(fileName: song?.artworkFileName, size: 48)
                Spacer(minLength: 4)
                if song != nil { WidgetPlaybackButton(snapshot: snapshot) }
            }
            Spacer(minLength: 6)
            WidgetTrackCaption(song: song)
            WidgetPlaybackProgress(snapshot: snapshot).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(MixtapeWidgetRoute.resume.url)
    }
}

struct RecentsWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var latest: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WidgetArtwork(fileName: latest?.artworkFileName, size: 48)
                WidgetTrackCaption(song: latest)
                if latest != nil { WidgetPlaybackButton(snapshot: snapshot) }
            }
            WidgetPlaybackProgress(snapshot: snapshot)
            if !snapshot.recentSongs.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(snapshot.recentSongs.prefix(4))) { song in
                        Link(destination: MixtapeWidgetRoute.play(videoId: song.videoId).url) {
                            WidgetArtwork(fileName: song.artworkFileName, size: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(song.title), \(song.artist)"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MixtapeWidgetRoute.resume.url)
    }
}

struct FavoritePlaylistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let playlist: MixtapeWidgetPlaylist?
    var snapshot: MixtapeWidgetSnapshot = .empty
    var body: some View { FavoritePlaylistContent(playlist: playlist, family: family, snapshot: snapshot) }
}

struct FavoritePlaylistContent: View {
    let playlist: MixtapeWidgetPlaylist?
    let family: WidgetFamily
    var snapshot: MixtapeWidgetSnapshot = .empty
    private var destination: URL {
        if let playlist, let id = UUID(uuidString: playlist.id) { return MixtapeWidgetRoute.playlist(id: id).url }
        return MixtapeWidgetRoute.library.url
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let playlist { Text(playlist.title) }
                else { Text("Choose a playlist", tableName: "WidgetStatus") }
            }
            .font(.system(size: family == .systemSmall ? 14 : 19, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(snapshot.currentSong == nil ? 2 : 1)
            if let current = snapshot.currentSong {
                Text(current.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 0 : 12) {
            if family == .systemSmall {
                HStack {
                    WidgetArtwork(fileName: playlist?.artworkFileName, size: 48, symbol: "music.note.list")
                    Spacer(minLength: 4)
                    WidgetPlaybackButton(snapshot: snapshot, playlistID: playlist?.id)
                }
                Spacer(minLength: 6)
                title
                WidgetPlaybackProgress(snapshot: snapshot).padding(.top, 8)
            } else {
                HStack(spacing: 14) {
                    WidgetArtwork(fileName: playlist?.artworkFileName, size: 64, symbol: "music.note.list")
                    title
                    WidgetPlaybackButton(snapshot: snapshot, playlistID: playlist?.id)
                }
                WidgetPlaybackProgress(snapshot: snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(destination)
    }
}

struct WidgetStorageNoticeView: View {
    let issue: MixtapeWidgetReadIssue
    private var title: String {
        switch issue {
        case .sharedContainerUnavailable: String(localized: "Data sharing unavailable", table: "WidgetStatus")
        case .noSnapshot: String(localized: "Open Mixtape first", table: "WidgetStatus")
        case .unreadableSnapshot: String(localized: "Refresh widget data", table: "WidgetStatus")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: issue == .sharedContainerUnavailable ? "exclamationmark.triangle" : "arrow.clockwise")
                .font(.system(size: 22, weight: .light)).foregroundStyle(WidgetStyle.red)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(2)
            Text("Check Widgets in Mixtape settings.", tableName: "WidgetStatus")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MixtapeWidgetRoute.library.url)
    }
}
