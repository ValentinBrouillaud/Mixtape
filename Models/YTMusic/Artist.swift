import Foundation

// MARK: - Artist

/// Represents an artist.
nonisolated struct Artist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let songCount: Int?

    /// Only associated YouTube channel browse IDs can open an artist page.
    /// Inline credits without an endpoint retain their generated identity for
    /// display and persistence, but must never become navigation destinations.
    nonisolated var hasNavigableBrowseID: Bool {
        let bytes = Array(id.utf8)
        guard bytes.count == 24, bytes[0] == 85, bytes[1] == 67 else { return false }
        return bytes.dropFirst(2).allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte)
                || (48...57).contains(byte) || byte == 95 || byte == 45
        }
    }

    init(id: String, name: String, thumbnailURL: URL? = nil, songCount: Int? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.songCount = songCount
    }
}

extension Artist {
    /// Creates an Artist from API response data.
    init?(from data: [String: Any]) {
        let name = (data["name"] as? String) ?? "Unknown Artist"

        // Artist ID is optional for inline references
        let artistId = (data["id"] as? String) ?? (data["browseId"] as? String) ?? UUID().uuidString

        self.id = artistId
        self.name = name

        // Parse thumbnail
        if let thumbnails = data["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let urlString = lastThumbnail["url"] as? String
        {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }

        // Parse song count if available (from subtitle like "42 songs")
        if let subtitle = data["subtitle"] as? String {
            let numbers = subtitle.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            self.songCount = Int(numbers)
        } else {
            self.songCount = nil
        }
    }
}
