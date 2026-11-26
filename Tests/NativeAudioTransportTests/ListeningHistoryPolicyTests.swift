import Foundation
import XCTest
@testable import NativeAudioTransport

final class ListeningHistoryPolicyTests: XCTestCase {
    func testRetainsOnlyTheLast100UniqueSongs() {
        var entries: [ListeningHistoryEntry] = []
        for index in 0..<105 {
            entries = ListeningHistoryPolicy.recording(entry("song-\(index)", timestamp: Double(index)), in: entries)
        }
        XCTAssertEqual(entries.count, 100)
        XCTAssertEqual(entries.first?.videoId, "song-104")
        XCTAssertEqual(entries.last?.videoId, "song-5")
    }

    func testListeningAgainMovesSongToFrontAndUpdatesMetadataWithoutDuplicatingIt() {
        let original = [entry("second", timestamp: 20), entry("first", timestamp: 10)]
        let replayed = ListeningHistoryEntry(
            videoId: "first", title: "Corrected title", artist: "Artist",
            artworkURL: URL(string: "https://example.com/cover.jpg"), duration: 180,
            lastPlayedAt: Date(timeIntervalSince1970: 30)
        )
        let updated = ListeningHistoryPolicy.recording(replayed, in: original)
        XCTAssertEqual(updated.map(\.videoId), ["first", "second"])
        XCTAssertEqual(updated.first, replayed)
    }

    func testRestoreKeepsPersistedOrderDespiteClockAdjustmentAndDropsDuplicates() {
        let latest = entry("latest", timestamp: 5)
        let earlier = entry("earlier", timestamp: 10)
        let normalized = ListeningHistoryPolicy.normalized([latest, earlier, latest, entry(" ", timestamp: 20)])
        XCTAssertEqual(normalized, [latest, earlier])
        XCTAssertEqual(ListeningHistoryPolicy.recording(entry("new", timestamp: 1), in: normalized).first?.videoId, "new")
    }

    func testReceiptRoundTripContainsOnlyDisplayMetadataAndOptionalArtistReferences() throws {
        var receipt = entry("video", timestamp: 40)
        receipt.artistCredits = [ListeningHistoryArtist(id: "UC-real-associated-artist", name: "Artist")]
        let data = try JSONEncoder().encode([receipt])
        XCTAssertEqual(try JSONDecoder().decode([ListeningHistoryEntry].self, from: data), [receipt])
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(objects.first).keys), ["videoId", "title", "artist", "lastPlayedAt", "artistCredits"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("streamURL"))

        // Entries created before optional artist identifiers existed remain readable.
        var fields = try XCTUnwrap(objects.first)
        fields.removeValue(forKey: "artistCredits")
        let oldData = try JSONSerialization.data(withJSONObject: [fields])
        XCTAssertNil(try JSONDecoder().decode([ListeningHistoryEntry].self, from: oldData).first?.artistCredits)
    }

    func testClickHighStartingPositionAndStalledPlayingStateDoNotCountAsListening() {
        var gate = ListeningProgressGate()
        XCTAssertFalse(gate.observe(isPlaying: true, position: 150, uptime: 0))
        for second in 1...20 {
            XCTAssertFalse(gate.observe(isPlaying: true, position: 150, uptime: Double(second)))
        }
        XCTAssertEqual(gate.listenedTime, 0)
        XCTAssertFalse(gate.hasQualified)
    }

    func testQualifiesOnlyAfterFiveAdvancingSecondsAndOnlyOncePerSession() {
        var gate = ListeningProgressGate()
        XCTAssertFalse(gate.observe(isPlaying: true, position: 0, uptime: 0))
        for second in 1..<5 {
            XCTAssertFalse(gate.observe(isPlaying: true, position: Double(second), uptime: Double(second)))
        }
        XCTAssertTrue(gate.observe(isPlaying: true, position: 5, uptime: 5))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 6, uptime: 6))
        XCTAssertTrue(gate.hasQualified)
    }

    func testPauseDoesNotCreditWallTimeButListeningCanAccumulateAcrossResume() {
        var gate = ListeningProgressGate()
        _ = gate.observe(isPlaying: true, position: 0, uptime: 0)
        _ = gate.observe(isPlaying: true, position: 3, uptime: 3)
        XCTAssertFalse(gate.observe(isPlaying: false, position: 3, uptime: 4))
        XCTAssertFalse(gate.observe(isPlaying: false, position: 3, uptime: 60))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 3, uptime: 61))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 4, uptime: 62))
        XCTAssertTrue(gate.observe(isPlaying: true, position: 5, uptime: 63))
        XCTAssertEqual(gate.listenedTime, 5)
    }

    func testForwardBackwardSeeksAndLongCallbackGapsDoNotInventListeningTime() {
        var gate = ListeningProgressGate()
        _ = gate.observe(isPlaying: true, position: 0, uptime: 0)
        XCTAssertFalse(gate.observe(isPlaying: true, position: 100, uptime: 0.2))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 5, uptime: 0.4))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 35, uptime: 30.4))
        XCTAssertEqual(gate.listenedTime, 0)
        for second in 1..<5 {
            XCTAssertFalse(gate.observe(isPlaying: true, position: 35 + Double(second), uptime: 30.4 + Double(second)))
        }
        XCTAssertTrue(gate.observe(isPlaying: true, position: 40, uptime: 35.4))
    }

    func testDuplicateTimerCallbacksPreserveAdvancingSampleAndInvalidValuesResetBaseline() {
        var gate = ListeningProgressGate()
        _ = gate.observe(isPlaying: true, position: 0, uptime: 0)
        XCTAssertFalse(gate.observe(isPlaying: true, position: 0, uptime: 0.5))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 1, uptime: 1))
        XCTAssertEqual(gate.listenedTime, 1)
        XCTAssertFalse(gate.observe(isPlaying: true, position: .nan, uptime: 2))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 10, uptime: 3))
        XCTAssertEqual(gate.listenedTime, 1)
        XCTAssertFalse(gate.observe(isPlaying: true, position: -1, uptime: 4))
        XCTAssertFalse(gate.observe(isPlaying: true, position: 0, uptime: .infinity))
    }

    private func entry(_ id: String, timestamp: TimeInterval) -> ListeningHistoryEntry {
        ListeningHistoryEntry(
            videoId: id, title: id, artist: "Artist", artworkURL: nil,
            duration: nil, lastPlayedAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}
