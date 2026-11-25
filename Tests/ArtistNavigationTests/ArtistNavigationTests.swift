import Foundation
import XCTest
@testable import ArtistNavigation

final class ArtistNavigationTests: XCTestCase {
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
