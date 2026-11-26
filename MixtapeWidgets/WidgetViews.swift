import Foundation
import ImageIO
import SwiftUI
import WidgetKit

enum WidgetStyle {
    static let red = Color(red: 0.92, green: 0.14, blue: 0.23)
    static let background = Color(red: 0.055, green: 0.06, blue: 0.07)
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
                Color.white.opacity(0.07)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.34, weight: .light))
                            .foregroundStyle(WidgetStyle.red)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14))
        .accessibilityHidden(true)
    }
}

private struct WidgetTrackCaption: View {
    let song: MixtapeWidgetSong?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let song {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            } else {
                Text("Open Mixtape", tableName: "WidgetStatus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ResumeWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var song: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetArtwork(fileName: song?.artworkFileName, size: 64)
            Spacer(minLength: 8)
            WidgetTrackCaption(song: song)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(MixtapeWidgetRoute.resume.url)
    }
}

struct RecentsWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var latest: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WidgetArtwork(fileName: latest?.artworkFileName, size: 56)
                WidgetTrackCaption(song: latest)
            }
            if !snapshot.recentSongs.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(snapshot.recentSongs.prefix(4))) { song in
                        Link(destination: MixtapeWidgetRoute.play(videoId: song.videoId).url) {
                            WidgetArtwork(fileName: song.artworkFileName, size: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(song.title) + Text(", ") + Text(song.artist))
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

    private var destination: URL {
        if let playlist, let id = UUID(uuidString: playlist.id) { return MixtapeWidgetRoute.playlist(id: id).url }
        return MixtapeWidgetRoute.library.url
    }

    private var title: some View {
        Group {
            if let playlist { Text(playlist.title) }
            else { Text("Choose a playlist", tableName: "WidgetStatus") }
        }
        .font(.system(size: family == .systemSmall ? 15 : 20, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetArtwork(fileName: playlist?.artworkFileName, size: 64, symbol: "music.note.list")
                    Spacer(minLength: 8)
                    title
                }
            } else {
                HStack(spacing: 16) {
                    WidgetArtwork(fileName: playlist?.artworkFileName, size: 80, symbol: "music.note.list")
                    title
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(destination)
        .accessibilityElement(children: .combine)
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
            Text(title)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            Text("Check Widgets in Mixtape settings.", tableName: "WidgetStatus")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MixtapeWidgetRoute.library.url)
    }
}
