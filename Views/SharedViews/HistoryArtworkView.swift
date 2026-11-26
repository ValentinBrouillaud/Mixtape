import ImageIO
import SwiftUI

/// Uses the durable history thumbnail first, including while offline after relaunch.
struct HistoryArtworkView: View {
    let videoId: String
    var size: CGFloat = 58
    @State private var cache = HistoryArtworkCache.shared

    var body: some View {
        Group {
            if let url = cache.cachedFileURL(videoId: videoId), let image = thumbnail(url) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 9))
    }

    private func thumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(size * 3),
        ] as CFDictionary)
    }
}
