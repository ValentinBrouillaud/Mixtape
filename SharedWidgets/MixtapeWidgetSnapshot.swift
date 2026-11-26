import Foundation

nonisolated struct MixtapeWidgetSong: Codable, Equatable, Identifiable, Sendable {
    let videoId: String
    let title: String
    let artist: String
    var artworkFileName: String?
    var id: String { videoId }
}

nonisolated struct MixtapeWidgetPlaylist: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let songCount: Int
    var artworkFileName: String?
}

nonisolated struct MixtapeWidgetSnapshot: Codable, Equatable, Sendable {
    var currentSong: MixtapeWidgetSong?
    var isPlaying: Bool
    var recentSongs: [MixtapeWidgetSong]
    var playlists: [MixtapeWidgetPlaylist]
    var updatedAt: Date
    var playback: MixtapeWidgetPlayback? = nil
    var appearance: String? = nil

    static var empty: Self {
        Self(currentSong: nil, isPlaying: false, recentSongs: [], playlists: [], updatedAt: .distantPast)
    }
}

nonisolated enum MixtapeWidgetRoute: Equatable, Sendable {
    case resume
    case library
    case play(videoId: String)
    case playlist(id: UUID)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "mixtape",
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        let fields = components.queryItems ?? []
        switch components.host?.lowercased() {
        case "resume" where fields.isEmpty:
            self = .resume
        case "library" where fields.isEmpty:
            self = .library
        case "play":
            guard fields.count == 1, fields[0].name == "videoId", let id = fields[0].value,
                  !id.isEmpty, id.count <= 128,
                  id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) else { return nil }
            self = .play(videoId: id)
        case "playlist":
            guard fields.count == 1, fields[0].name == "id", let value = fields[0].value,
                  let id = UUID(uuidString: value) else { return nil }
            self = .playlist(id: id)
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "mixtape"
        switch self {
        case .resume:
            components.host = "resume"
        case .library:
            components.host = "library"
        case .play(let videoId):
            components.host = "play"
            components.queryItems = [URLQueryItem(name: "videoId", value: videoId)]
        case .playlist(let id):
            components.host = "playlist"
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        }
        return components.url!
    }
}
