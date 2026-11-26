import AppKit
import Foundation
import ImageIO
import SwiftUI
import WidgetKit

/// Render the actual views on the CI Mac. These are layout previews rather
/// than screenshots from signed iPhone widgets.
@main
@MainActor
enum WidgetPreviewRenderer {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let artwork = MixtapeWidgetKeychain.artworkDirectory
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        var temporaryCovers: [URL] = []
        defer { for url in temporaryCovers { try? FileManager.default.removeItem(at: url) } }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.64, 0.14, 0.21), (0.18, 0.32, 0.57), (0.24, 0.40, 0.33), (0.59, 0.37, 0.18)]
        var songs: [MixtapeWidgetSong] = []
        for (index, color) in colors.enumerated() {
            let name = "mixtape-layout-preview-\(UUID().uuidString).jpg"
            let url = artwork.appendingPathComponent(name)
            temporaryCovers.append(url)
            try cover(at: url, color: color)
            songs.append(MixtapeWidgetSong(videoId: "preview-\(index)", title: index == 0 ? "Minuit sur la route" : "Echo \(index)",
                artist: "Nova", artworkFileName: name))
        }
        let snapshot = MixtapeWidgetSnapshot(currentSong: songs[0], isPlaying: false, recentSongs: songs, playlists: [], updatedAt: Date())
        let playlist = MixtapeWidgetPlaylist(id: UUID().uuidString, title: "Les favoris", songCount: 24, artworkFileName: songs[2].artworkFileName)
        let resume = widget(ResumeWidgetView(snapshot: snapshot), family: .systemSmall)
        let recents = widget(RecentsWidgetView(snapshot: snapshot), family: .systemMedium)
        let smallPlaylist = widget(FavoritePlaylistContent(playlist: playlist, family: .systemSmall), family: .systemSmall)
        let mediumPlaylist = widget(FavoritePlaylistContent(playlist: playlist, family: .systemMedium), family: .systemMedium)
        try render(resume, to: output.appendingPathComponent("resume-small.png"))
        try render(recents, to: output.appendingPathComponent("recents-medium.png"))
        try render(smallPlaylist, to: output.appendingPathComponent("playlist-small.png"))
        try render(mediumPlaylist, to: output.appendingPathComponent("playlist-medium.png"))
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
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.locale, Locale(identifier: "fr"))
        try render(overview, to: output.appendingPathComponent("widget-overview.png"))
        try render(widget(ResumeWidgetView(snapshot: .empty), family: .systemSmall, smallWidth: 148),
            to: output.appendingPathComponent("empty-small-148.png"))
        try render(widget(WidgetStorageNoticeView(issue: .sharedContainerUnavailable), family: .systemSmall, smallWidth: 148),
            to: output.appendingPathComponent("notice-small-148.png"))
        print("Rendered 7 widget layout previews from the app's SwiftUI views.")
    }

    private static func widget<V: View>(_ view: V, family: WidgetFamily, smallWidth: CGFloat = 158) -> some View {
        view.padding(16)
            .frame(width: family == .systemSmall ? smallWidth : 338, height: smallWidth)
            .background(WidgetStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, .dark)
    }

    private static func panel<V: View>(_ title: String, content: V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.black.opacity(0.65))
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

    private static func cover(at url: URL, color: (CGFloat, CGFloat, CGFloat)) throws {
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
    }
}
