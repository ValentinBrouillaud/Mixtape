import Foundation
import XCTest
@testable import NativeAudioTransport

final class PlaybackQueueTests: XCTestCase {
    func testAdditionsAreFIFOAheadOfPlaylistWhilePlayNextIsImmediate() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["current", "playlist A", "playlist B"])
        queue.insert(["manual A"], placement: .afterUserAdditions)
        queue.insert(["manual B", "manual C"], placement: .afterUserAdditions)
        queue.insert(["urgent"], placement: .next)
        XCTAssertEqual(queue.entries.map(\.track), ["current", "urgent", "manual A", "manual B", "manual C", "playlist A", "playlist B"])
    }

    func testEndPlacementDoesNotChangeCurrentOrPriorityBlock() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["current", "playlist"])
        let current = queue.current?.id
        queue.insert(["last"], placement: .end)
        queue.insert(["manual"], placement: .afterUserAdditions)
        XCTAssertEqual(queue.entries.map(\.track), ["current", "manual", "playlist", "last"])
        XCTAssertEqual(queue.current?.id, current)
    }

    func testDuplicateVideosHaveSeparateRemovalAndMoveIdentities() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["same", "same", "other", "same"])
        let current = queue.current!.id
        let removed = queue.entries[1].id
        let moved = queue.entries[3].id
        queue.remove(ids: [removed, current])
        queue.moveToNext(id: moved)
        XCTAssertEqual(queue.entries.map(\.track), ["same", "same", "other"])
        XCTAssertEqual(queue.entries[1].id, moved)
        XCTAssertEqual(queue.current?.id, current)
        XCTAssertFalse(queue.entries.contains { $0.id == removed })
    }

    func testReorderUpcomingCannotMoveCurrentOrDropOmittedDuplicate() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["past", "current", "same", "same", "last"], startingAt: 1)
        let current = queue.current!.id
        let last = queue.entries[4].id
        queue.reorderUpcoming(ids: [last, last, current, UUID()])
        XCTAssertEqual(queue.entries.map(\.track), ["past", "current", "last", "same", "same"])
        XCTAssertEqual(queue.current?.id, current)
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testDragMoveUsesVisibleUpcomingOffsetsWithoutChangingPlayingOccurrence() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["past", "current", "A", "B", "C"], startingAt: 1)
        let current = queue.current!.id
        queue.moveUpcoming(from: [0, 2], to: 2)
        XCTAssertEqual(queue.entries.map(\.track), ["past", "current", "B", "A", "C"])
        XCTAssertEqual(queue.current?.id, current)
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testRadioSuggestionsAppendWithoutReplacingManualAdditions() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["seed"])
        queue.insert(["manual"], placement: .afterUserAdditions)
        queue.appendSource(["radio A", "radio B"])
        XCTAssertEqual(queue.entries.map(\.track), ["seed", "manual", "radio A", "radio B"])
    }

    func testQueueWithoutPlaybackDoesNotSilentlySelectOrSkipFirstAddition() {
        var queue = PlaybackQueue<String>()
        queue.insert(["first", "second"], placement: .afterUserAdditions)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.upcoming.map(\.track), ["first", "second"])
        XCTAssertTrue(queue.select(0))
        XCTAssertEqual(queue.current?.track, "first")
    }

    func testRemovingPlayedOccurrencesKeepsCurrentDuplicateAndItsAdjustedIndex() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["same", "old", "same", "future"], startingAt: 2)
        let current = queue.current!.id
        queue.remove(ids: [queue.entries[0].id, queue.entries[1].id])
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(queue.current?.id, current)
        XCTAssertEqual(queue.entries.map(\.track), ["same", "future"])
    }

    func testPersistedOccurrenceIDsFlagsAndSelectionRoundTrip() throws {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["past", "current", "same", "same"], startingAt: 1)
        queue.insert(["manual"], placement: .afterUserAdditions)
        let decoded = try JSONDecoder().decode(PlaybackQueue<String>.self, from: JSONEncoder().encode(queue))
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.entries.map(\.id), queue.entries.map(\.id))
        XCTAssertEqual(decoded.entries.map(\.isUserAdded), queue.entries.map(\.isUserAdded))
        XCTAssertEqual(decoded.currentIndex, 1)
    }

    func testShuffleNeverChangesManualOrderOrCurrentIdentity() {
        var queue = PlaybackQueue<String>()
        queue.replace(with: ["current", "A", "B", "C", "D"])
        queue.insert(["manual A", "manual B"], placement: .afterUserAdditions)
        let original = queue.entries.map(\.id)
        var rng = SystemRandomNumberGenerator()
        queue.shuffleUpcoming(using: &rng)
        XCTAssertEqual(Array(queue.entries.prefix(3)).map(\.track), ["current", "manual A", "manual B"])
        XCTAssertEqual(Set(queue.entries.map(\.id)), Set(original))
    }
}
