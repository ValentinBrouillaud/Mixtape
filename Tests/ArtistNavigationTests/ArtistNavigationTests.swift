import Foundation
import XCTest
@testable import ArtistNavigation

final class ArtistNavigationTests: XCTestCase {
    func testCorrectedOfflineDurationRetainsIdentityArtistsAndLibraryMetadata() throws {
        let artist = Artist(id: "UC_x5XG1OV2P6uZZ5FSM9Ttw", name: "Associated artist")
        let source = Song(id: "song", title: "Song", artists: [artist], duration: 600,
                          thumbnailURL: URL(string: "https://example.com/cover.jpg"), videoId: "video",
                          videoType: .atv, likeStatus: .like, isInLibrary: true,
                          feedbackTokens: FeedbackTokens(add: "add", remove: "remove"))
        let corrected = source.withDuration(180.2)
        let restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(corrected))
        XCTAssertEqual(restored.duration, 180.2)
        XCTAssertEqual(restored.id, source.id)
        XCTAssertEqual(restored.videoId, source.videoId)
        XCTAssertEqual(restored.artists, source.artists)
        XCTAssertEqual(restored.thumbnailURL, source.thumbnailURL)
        XCTAssertEqual(restored.likeStatus, source.likeStatus)
        XCTAssertEqual(restored.isInLibrary, source.isInLibrary)
        XCTAssertEqual(restored.feedbackTokens, source.feedbackTokens)
        XCTAssertEqual(source.withDuration(.nan).duration, 600)
    }

    func testAssociatedChannelBrowseIDCanNavigate() {
        XCTAssertTrue(Artist(id: "UC_x5XG1OV2P6uZZ5FSM9Ttw", name: "Associated artist").hasNavigableBrowseID)
        XCTAssertTrue(Artist(id: "UC-abcDEF0123456789_-abc", name: "Associated artist").hasNavigableBrowseID)
    }

    func testInlineCreditsWithoutChannelEndpointCannotNavigate() {
        for id in [UUID().uuidString, "unknown", "", "UC", "UCartist", "MPREb_album", "UC_x5XG1OV2P6uZZ5FSM9Tt/"] {
            XCTAssertFalse(Artist(id: id, name: "Inline credit").hasNavigableBrowseID, id)
        }
    }

    func testCodablePreservesExistingArtistAssociation() throws {
        let artist = Artist(id: "UC_x5XG1OV2P6uZZ5FSM9Ttw", name: "Associated artist")
        let saved = try JSONEncoder().encode(artist)
        let restored = try JSONDecoder().decode(Artist.self, from: saved)
        XCTAssertEqual(restored.id, artist.id)
        XCTAssertTrue(restored.hasNavigableBrowseID)
    }
}
