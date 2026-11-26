import Foundation
import ImageIO

/// Persist icon-sized pixels, rather than making every widget decode a full
/// remote cover. This utility does not perform network or audio requests.
nonisolated enum HistoryThumbnail {
    static let maximumInputBytes = 1_000_000

    static func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), encoded.length <= maximumInputBytes else {
            throw CocoaError(.fileWriteUnknown)
        }
        return encoded as Data
    }
}
