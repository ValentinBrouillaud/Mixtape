import Foundation
import XCTest
@testable import SharedWidgetModel

final class WidgetSnapshotTests: XCTestCase {
    func testDeepLinksRoundTripForApprovedForegroundActions() {
        for route: MixtapeWidgetRoute in [.resume, .library, .play(videoId: "dQw4w9WgXcQ"), .playlist(id: UUID())] {
            XCTAssertEqual(MixtapeWidgetRoute(url: route.url), route)
        }
    }

    func testRejectsUnknownRoutesDuplicateQueriesAndInvalidIDs() throws {
        for value in [
            "https://resume", "mixtape://pause", "mixtape://resume/unexpected", "mixtape://resume?autoplay=true",
            "mixtape://play?videoId=one&videoId=two", "mixtape://play?videoId=", "mixtape://play?videoId=one/../../audio",
            "mixtape://play?videoId=one&extra=value", "mixtape://playlist?id=not-a-uuid", "mixtape://playlist?id=",
            "mixtape://user:password@resume", "mixtape://resume:80", "mixtape://play?videoId=hello%20world",
        ] {
            XCTAssertNil(MixtapeWidgetRoute(url: try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testSnapshotRoundTripPreservesMetadataWithoutAudioOrAuthentication() throws {
        let song = MixtapeWidgetSong(videoId: "video", title: "Title", artist: "Artist", artworkFileName: "thumbnail.jpg")
        let snapshot = MixtapeWidgetSnapshot(
            currentSong: song, isPlaying: false, recentSongs: [song],
            playlists: [MixtapeWidgetPlaylist(id: UUID().uuidString, title: "Favorites", songCount: 9)],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(MixtapeWidgetSnapshot.self, from: data), snapshot)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("streamURL"))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("authorization"))
    }

    func testArtworkDoesNotAcceptPathsOutsideTheSharedArtworkFolder() {
        for name in [nil, "", "..", ".", "../audio.m4a", "/private/audio.m4a", "folder/cover.jpg"] {
            XCTAssertNil(MixtapeWidgetStorage.artworkURL(fileName: name))
        }
    }
}
