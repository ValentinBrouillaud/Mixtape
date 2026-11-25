import SwiftUI
import Foundation
import UIKit
import WidgetKit

@main
struct MixtapeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MixtapeResumeWidget()
        MixtapeRecentsWidget()
        MixtapeFavoritePlaylistWidget()
    }
}

struct MixtapeTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: MixtapeWidgetSnapshot
}

struct MixtapeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MixtapeTimelineEntry {
        MixtapeTimelineEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MixtapeTimelineEntry) -> Void) {
        completion(MixtapeTimelineEntry(date: Date(), snapshot: MixtapeWidgetStorage.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MixtapeTimelineEntry>) -> Void) {
        let entry = MixtapeTimelineEntry(date: Date(), snapshot: MixtapeWidgetStorage.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 30))))
    }
}

private enum WidgetStyle {
    static let red = Color(red: 0.92, green: 0.14, blue: 0.23)
    static let background = Color(red: 0.055, green: 0.06, blue: 0.07)
}

private struct WidgetArtwork: View {
    let song: MixtapeWidgetSong?
    let size: CGFloat
    var body: some View {
        Group {
            if let url = MixtapeWidgetStorage.artworkURL(fileName: song?.artworkFileName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").font(.system(size: size * 0.38)).foregroundStyle(WidgetStyle.red)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
        .accessibilityHidden(true)
    }
}

private struct WidgetBrand: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform").foregroundStyle(WidgetStyle.red)
            Text("MIXTAPE").tracking(1.1).foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 9, weight: .bold))
    }
}

struct MixtapeResumeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MixtapeResume", provider: MixtapeTimelineProvider()) { entry in
            ResumeWidgetView(snapshot: entry.snapshot)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Resume")
        .description("Open Mixtape and resume your music.")
        .supportedFamilies([.systemSmall])
    }
}

private struct ResumeWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var song: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetBrand()
            HStack {
                WidgetArtwork(song: song, size: 42)
                Spacer(minLength: 4)
                Image(systemName: "play.circle.fill").font(.system(size: 31)).foregroundStyle(WidgetStyle.red)
            }
            if let song {
                Text(song.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(song.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            } else {
                Text("Your music, ready").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("Open Mixtape").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            Text("Resume").font(.system(size: 10, weight: .bold)).foregroundStyle(WidgetStyle.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MixtapeWidgetRoute.resume.url)
    }
}

struct MixtapeRecentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MixtapeRecents", provider: MixtapeTimelineProvider()) { entry in
            RecentsWidgetView(snapshot: entry.snapshot)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Recent Listening")
        .description("Your latest song and four recent favorites, ready to open in Mixtape.")
        .supportedFamilies([.systemMedium])
    }
}

private struct RecentsWidgetView: View {
    let snapshot: MixtapeWidgetSnapshot
    private var latest: MixtapeWidgetSong? { snapshot.currentSong ?? snapshot.recentSongs.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { WidgetBrand(); Spacer(); Image(systemName: "clock.arrow.circlepath").foregroundStyle(WidgetStyle.red).font(.caption) }
            HStack(spacing: 11) {
                WidgetArtwork(song: latest, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    if let latest {
                        Text(latest.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(latest.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    } else {
                        Text("Your music, ready").font(.headline).foregroundStyle(.white)
                        Text("Open Mixtape").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(WidgetStyle.red)
            }
            HStack(spacing: 7) {
                ForEach(Array(snapshot.recentSongs.prefix(4))) { song in
                    Link(destination: MixtapeWidgetRoute.play(videoId: song.videoId).url) {
                        WidgetArtwork(song: song, size: 29)
                    }
                    .accessibilityLabel(song.title)
                }
                Spacer(minLength: 0)
                Text("Recently played").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MixtapeWidgetRoute.resume.url)
    }
}

struct MixtapeFavoritePlaylistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MixtapeFavoritePlaylist", intent: FavoritePlaylistIntent.self, provider: FavoritePlaylistProvider()) { entry in
            FavoritePlaylistWidgetView(playlist: entry.playlist)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Favorite Playlist")
        .description("Choose a Mixtape playlist to open with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct FavoritePlaylistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let playlist: MixtapeWidgetPlaylist?
    private var destination: URL {
        if let playlist, let id = UUID(uuidString: playlist.id) { return MixtapeWidgetRoute.playlist(id: id).url }
        return MixtapeWidgetRoute.library.url
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetBrand()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Favorite Playlist").font(.system(size: 10, weight: .bold)).foregroundStyle(WidgetStyle.red)
                    if let playlist {
                        Text(playlist.title).font(.system(size: family == .systemSmall ? 16 : 20, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                        Text("\(playlist.songCount) songs").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text("Choose a playlist").font(.headline).foregroundStyle(.white).lineLimit(2)
                        Text("Open Mixtape").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
                if family == .systemMedium {
                    if let url = MixtapeWidgetStorage.artworkURL(fileName: playlist?.artworkFileName),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: "music.note.list").font(.system(size: 32, weight: .light)).foregroundStyle(WidgetStyle.red)
                            .frame(width: 68, height: 68)
                            .background(WidgetStyle.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("Open playlist").font(.system(size: 10, weight: .bold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(WidgetStyle.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(destination)
    }
}
