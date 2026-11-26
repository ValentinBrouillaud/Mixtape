import AppKit
import Foundation
import ImageIO
import SwiftUI
import WidgetKit

/// Native layouts using demo metadata; these are not signed iPhone screenshots.
@main
@MainActor
enum WidgetPreviewRenderer {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let directory = MixtapeWidgetKeychain.artworkDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var temporaryCovers: [URL] = []
        defer { for url in temporaryCovers { try? FileManager.default.removeItem(at: url) } }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.64, 0.14, 0.21), (0.18, 0.32, 0.57), (0.24, 0.40, 0.33), (0.59, 0.37, 0.18)]
        let titles = ["Minuit sur la route", "Echo", "Les jours bleus", "Au grand air"]
        var songs: [MixtapeWidgetSong] = []
        var covers: [CGImage] = []
        for (index, color) in colors.enumerated() {
            let name = "mixtape-layout-preview-\(UUID().uuidString).jpg"
            let url = directory.appendingPathComponent(name)
            temporaryCovers.append(url)
            covers.append(try cover(at: url, color: color))
            songs.append(MixtapeWidgetSong(videoId: "preview-\(index)", title: titles[index], artist: "Nova", artworkFileName: name))
        }
        var snapshot = MixtapeWidgetSnapshot(currentSong: songs[0], isPlaying: true, recentSongs: songs, playlists: [], updatedAt: Date())
        snapshot.playback = .init(videoID: songs[0].videoId, position: 63, duration: 210, sampledAt: Date(), isAdvancing: true)
        let playlist = MixtapeWidgetPlaylist(id: UUID().uuidString, title: "Les favoris", songCount: 24, artworkFileName: songs[2].artworkFileName)
        for scheme in [ColorScheme.dark, .light] {
            let label = scheme == .dark ? "dark" : "light"
            var paused = snapshot
            paused.isPlaying = false
            paused.playback = .init(videoID: songs[0].videoId, position: 63, duration: 210, sampledAt: Date(), isAdvancing: false)
            let resume = widget(ResumeWidgetView(snapshot: snapshot), family: .systemSmall, scheme: scheme)
            let recents = widget(RecentsWidgetView(snapshot: snapshot), family: .systemMedium, scheme: scheme)
            let smallPlaylist = widget(FavoritePlaylistContent(playlist: playlist, family: .systemSmall, snapshot: snapshot), family: .systemSmall, scheme: scheme)
            let mediumPlaylist = widget(FavoritePlaylistContent(playlist: playlist, family: .systemMedium, snapshot: snapshot), family: .systemMedium, scheme: scheme)
            try render(resume, to: output.appendingPathComponent("resume-small-\(label).png"))
            try render(recents, to: output.appendingPathComponent("recents-medium-\(label).png"))
            try render(smallPlaylist, to: output.appendingPathComponent("playlist-small-\(label).png"))
            try render(mediumPlaylist, to: output.appendingPathComponent("playlist-medium-\(label).png"))
            try render(widget(ResumeWidgetView(snapshot: paused), family: .systemSmall, scheme: scheme, smallWidth: 148),
                to: output.appendingPathComponent("paused-small-148-\(label).png"))
            try render(widget(ResumeWidgetView(snapshot: .empty), family: .systemSmall, scheme: scheme, smallWidth: 148),
                to: output.appendingPathComponent("empty-small-148-\(label).png"))
            try render(widget(WidgetStorageNoticeView(issue: .sharedContainerUnavailable), family: .systemSmall, scheme: scheme, smallWidth: 148),
                to: output.appendingPathComponent("notice-small-148-\(label).png"))
            let overview = VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    panel("Reprendre · Petit", content: resume)
                    panel("Récents · Moyen", content: recents)
                }
                HStack(alignment: .top, spacing: 24) {
                    panel("Playlist · Petit", content: smallPlaylist)
                    panel("Playlist · Moyen", content: mediumPlaylist)
                }
            }
            .padding(24).background(Color(white: scheme == .dark ? 0.025 : 0.92))
            .environment(\.colorScheme, scheme)
            try render(overview, to: output.appendingPathComponent("widget-overview-\(label).png"))
            let app = home(covers: covers, titles: titles).environment(\.colorScheme, scheme)
            let player = fullPlayer(image: covers[0]).environment(\.colorScheme, scheme).frame(width: 390, height: 760)
            try render(app, to: output.appendingPathComponent("app-home-\(label).png"))
            try render(player, to: output.appendingPathComponent("app-player-\(label).png"))
            try render(fullPlayer(image: covers[0]).environment(\.colorScheme, scheme).frame(width: 320, height: 568),
                to: output.appendingPathComponent("app-player-compact-\(label).png"))
            try render(HStack(alignment: .top, spacing: 20) { app; player }.padding(24)
                .background(Color(white: scheme == .dark ? 0.025 : 0.92)),
                to: output.appendingPathComponent("app-overview-\(label).png"))
        }
        print("Rendered 24 light/dark app and widget layout previews using demo metadata.")
    }

    private static func art(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
    }

    private static func home(covers: [CGImage], titles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(MixtapePalette.accent)
                Text("Accueil").font(.system(size: 24, weight: .bold))
                Spacer()
            }.padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Écoutés récemment").font(.system(size: 23, weight: .bold))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(0..<4) { index in
                                MixtapeRecentTile(title: titles[index], onPlay: {}) { art(covers[index]) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pour vous").font(.system(size: 23, weight: .bold))
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(1..<3) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    art(covers[index]).frame(width: 169, height: 169).clipShape(RoundedRectangle(cornerRadius: 5))
                                    Text(titles[index]).font(.system(size: 14, weight: .semibold))
                                    Text("Nova").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("Vos découvertes").font(.system(size: 23, weight: .bold))
                    HStack(spacing: 12) {
                        art(covers[3]).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Au grand air").font(.system(size: 15, weight: .semibold))
                            Text("Nova").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            VStack(spacing: 6) {
                MixtapeMiniPlayerLayout(title: titles[0], artist: "Nova", isPlaying: true, fraction: 0.3,
                    onOpen: {}, onPlayPause: {}, onNext: {}) { art(covers[0]) }.padding(.horizontal, 8)
                MixtapeBottomNavigation(selected: .home, onSelect: { _ in })
            }.padding(.top, 6).padding(.bottom, 20)
        }
        .frame(width: 390, height: 760).mixtapeScreenStyle()
    }

    private static func fullPlayer(image: CGImage) -> some View {
        MixtapeFullPlayerLayout(sourceTitle: "Les favoris", showsPanel: false, onDismiss: {}) {
            art(image)
        } info: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minuit sur la route").font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    Text("Nova").font(.system(size: 17)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.down.circle").font(.system(size: 23))
                Image(systemName: "airplay.audio").font(.system(size: 23))
                Image(systemName: "ellipsis").font(.system(size: 23))
            }
        } progress: {
            VStack(spacing: 6) {
                ProgressView(value: 0.3).tint(MixtapePalette.accent)
                HStack { Text("1:03"); Spacer(); Text("-2:27") }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } controls: {
            HStack(spacing: 44) {
                Image(systemName: "backward.fill").font(.system(size: 26, weight: .medium))
                Image(systemName: "pause.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(MixtapePalette.accent, in: Circle())
                Image(systemName: "forward.fill").font(.system(size: 26, weight: .medium))
            }
        } actions: {
            HStack(spacing: 44) {
                ForEach(["shuffle", "quote.bubble.fill", "list.bullet", "repeat"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 20)).foregroundStyle(.secondary)
                }
            }
        } panel: { EmptyView() }
    }

    private static func widget<V: View>(_ view: V, family: WidgetFamily, scheme: ColorScheme, smallWidth: CGFloat = 158) -> some View {
        view.padding(16)
            .frame(width: family == .systemSmall ? smallWidth : 338, height: smallWidth)
            .background(MixtapePalette.background(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, scheme)
    }

    private static func panel<V: View>(_ title: String, content: V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            content
        }
    }

    private static func render<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func cover(at url: URL, color: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.20)
        context.fillEllipse(in: CGRect(x: 55, y: 55, width: 180, height: 180))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.20)
        context.fill(CGRect(x: 0, y: 0, width: 110, height: 256))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return image
    }
}
