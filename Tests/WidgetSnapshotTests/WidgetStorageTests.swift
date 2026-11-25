import Foundation
import XCTest
@testable import SharedWidgetModel

final class WidgetStorageTests: XCTestCase {
    func testReadsSongTitlesAndPlaylistConfigurationFromActualSnapshotFile() throws {
        try withDirectory { root in
            let expected = snapshot(title: "A real song title")
            try save(expected, in: root)
            let result = MixtapeWidgetStorage.read(at: root)
            XCTAssertNil(result.issue)
            XCTAssertEqual(result.snapshot, expected)
            XCTAssertEqual(result.snapshot.currentSong?.title, "A real song title")
            XCTAssertEqual(result.snapshot.playlists.first?.title, "Selected playlist")
        }
    }

    func testAtomicSnapshotReplacementIsVisibleOnTheNextRead() throws {
        try withDirectory { root in
            try save(snapshot(title: "Before"), in: root)
            XCTAssertEqual(MixtapeWidgetStorage.read(at: root).snapshot.currentSong?.title, "Before")
            try save(snapshot(title: "After"), in: root)
            XCTAssertEqual(MixtapeWidgetStorage.read(at: root).snapshot.currentSong?.title, "After")
        }
    }

    func testValidEmptySnapshotIsDifferentFromMissingSharedData() throws {
        try withDirectory { root in
            try save(.empty, in: root)
            let result = MixtapeWidgetStorage.read(at: root)
            XCTAssertEqual(result.snapshot, .empty)
            XCTAssertNil(result.issue)
        }
    }

    func testUnavailableContainerAndMissingSnapshotHaveDifferentReasons() throws {
        XCTAssertEqual(MixtapeWidgetStorage.read(at: nil).issue, .sharedContainerUnavailable)
        try withDirectory { root in
            XCTAssertEqual(MixtapeWidgetStorage.read(at: root).issue, .noSnapshot)
            XCTAssertEqual(MixtapeWidgetStorage.read(at: root.appendingPathComponent("missing-directory")).issue, .noSnapshot)
        }
    }

    func testCorruptEmptyAndOversizedSnapshotsFailWithoutShowingPartialTitles() throws {
        try withDirectory { root in
            for data in [Data(), Data("{\"currentSong\":".utf8), Data(repeating: 32, count: 2 * 1024 * 1024 + 1)] {
                try data.write(to: root.appendingPathComponent(MixtapeWidgetStorage.snapshotFileName), options: .atomic)
                let result = MixtapeWidgetStorage.read(at: root)
                XCTAssertEqual(result.issue, .unreadableSnapshot)
                XCTAssertNil(result.snapshot.currentSong)
            }
        }
    }

    func testReadingFromTheAppDoesNotManufactureAWidgetReceipt() throws {
        try withDirectory { root in
            try save(snapshot(title: "A title"), in: root)
            XCTAssertNil(MixtapeWidgetStorage.read(at: root).issue)
            XCTAssertNil(MixtapeWidgetStorage.lastReceipt(at: root))
        }
    }

    func testExplicitWidgetAcknowledgementPersistsTheReadSnapshotAndGroup() throws {
        try withDirectory { root in
            let expected = snapshot(title: "Received by extension")
            try save(expected, in: root)
            let readAt = Date(timeIntervalSince1970: 1234)
            let identifier = "group.personal.Mixtape.shared"
            XCTAssertTrue(MixtapeWidgetStorage.acknowledge(
                MixtapeWidgetStorage.read(at: root), in: root, appGroupIdentifier: identifier, at: readAt
            ))
            let receipt = try XCTUnwrap(MixtapeWidgetStorage.lastReceipt(at: root))
            XCTAssertEqual(receipt.readAt, readAt)
            XCTAssertEqual(receipt.snapshotUpdatedAt, expected.updatedAt)
            XCTAssertEqual(receipt.appGroupIdentifier, identifier)
        }
    }

    func testFailedReadsAndUnknownGroupCannotClaimTheWidgetReceivedData() throws {
        try withDirectory { root in
            for issue in [MixtapeWidgetReadIssue.sharedContainerUnavailable, .noSnapshot, .unreadableSnapshot] {
                XCTAssertFalse(MixtapeWidgetStorage.acknowledge(
                    MixtapeWidgetReadResult(snapshot: .empty, issue: issue),
                    in: root, appGroupIdentifier: "group.Mixtape.shared"
                ))
            }
            XCTAssertFalse(MixtapeWidgetStorage.acknowledge(
                MixtapeWidgetReadResult(snapshot: .empty, issue: nil), in: root, appGroupIdentifier: nil
            ))
            XCTAssertNil(MixtapeWidgetStorage.lastReceipt(at: root))
        }
    }

    func testCorruptReceiptIsIgnored() throws {
        try withDirectory { root in
            try Data("not a receipt".utf8).write(to: root.appendingPathComponent(MixtapeWidgetStorage.receiptFileName))
            XCTAssertNil(MixtapeWidgetStorage.lastReceipt(at: root))
        }
    }

    private func snapshot(title: String) -> MixtapeWidgetSnapshot {
        let song = MixtapeWidgetSong(videoId: "video-id", title: title, artist: "Artist", artworkFileName: "cover.image")
        return MixtapeWidgetSnapshot(
            currentSong: song, isPlaying: true, recentSongs: [song],
            playlists: [MixtapeWidgetPlaylist(id: "E68A243A-0A3B-40B5-BD69-A7C36BC6DCAA", title: "Selected playlist", songCount: 12)],
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    private func save(_ snapshot: MixtapeWidgetSnapshot, in root: URL) throws {
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent(MixtapeWidgetStorage.snapshotFileName), options: .atomic)
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mixtape-widget-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
