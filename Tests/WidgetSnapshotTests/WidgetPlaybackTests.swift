import Foundation
import XCTest
@testable import SharedWidgetModel

final class WidgetPlaybackTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1000)

    func testPlayingProgressAdvancesFromItsAnchorAndStopsAtTheTrackEnd() {
        let value = playback(position: 30, duration: 120, advancing: true)
        XCTAssertEqual(value.position(at: date.addingTimeInterval(20)), 50)
        XCTAssertEqual(value.position(at: date.addingTimeInterval(200)), 120)
        XCTAssertEqual(value.fraction(at: date.addingTimeInterval(200)), 1)
        XCTAssertEqual(value.timerInterval?.lowerBound, date.addingTimeInterval(-30))
        XCTAssertEqual(value.timerInterval?.upperBound, date.addingTimeInterval(90))
    }

    func testPauseFreezesProgressAndRemovesTheAutomaticTimer() {
        let value = playback(position: 45, duration: 120, advancing: false)
        XCTAssertEqual(value.position(at: date.addingTimeInterval(600)), 45)
        XCTAssertEqual(value.fraction(at: date.addingTimeInterval(600)), 0.375)
        XCTAssertNil(value.timerInterval)
    }

    func testUnknownOrInvalidDurationCannotManufactureAProgressInterval() {
        for duration in [nil, 0, -1, Double.nan, Double.infinity] as [Double?] {
            let value = playback(position: 12, duration: duration, advancing: true)
            XCTAssertNil(value.timerInterval)
            XCTAssertEqual(value.fraction(at: date), 0)
        }
    }

    func testInvalidPositionsAndDatesAreSanitizedBeforeTheyReachTheSharedJSON() throws {
        for position in [Double.nan, Double.infinity, -10] {
            let value = MixtapeWidgetPlayback(videoID: "track", position: position, duration: 120,
                sampledAt: Date(timeIntervalSinceReferenceDate: .infinity), isAdvancing: false)
            XCTAssertEqual(value.position, 0)
            XCTAssertTrue(value.sampledAt.timeIntervalSinceReferenceDate.isFinite)
            XCTAssertNoThrow(try JSONEncoder().encode(value))
        }
    }

    func testOrdinaryPlaybackTicksDoNotRepublishTheWidgetEverySecond() {
        let first = playback(position: 30, duration: 120, advancing: true)
        let later = MixtapeWidgetPlayback(videoID: "track", position: 60, duration: 120,
            sampledAt: date.addingTimeInterval(30), isAdvancing: true)
        XCTAssertFalse(later.needsPublication(after: first))
    }

    func testSeekingPublishesANewAnchorImmediately() {
        let first = playback(position: 30, duration: 120, advancing: true)
        let sought = MixtapeWidgetPlayback(videoID: "track", position: 80, duration: 120,
            sampledAt: date.addingTimeInterval(1), isAdvancing: true)
        XCTAssertTrue(sought.needsPublication(after: first))
    }

    func testPauseAndResumeRequireFreshWidgetState() {
        let playing = playback(position: 30, duration: 120, advancing: true)
        let paused = playback(position: 30, duration: 120, advancing: false)
        XCTAssertTrue(paused.needsPublication(after: playing))
        XCTAssertTrue(playing.needsPublication(after: paused))
    }

    func testNewDurationAndNewTrackRequireFreshWidgetState() {
        let first = playback(position: 30, duration: nil, advancing: true)
        XCTAssertTrue(playback(position: 30, duration: 120, advancing: true).needsPublication(after: first))
        let next = MixtapeWidgetPlayback(videoID: "next", position: 30, duration: nil, sampledAt: date, isAdvancing: true)
        XCTAssertTrue(next.needsPublication(after: first))
    }

    func testClockMovingBackwardsDoesNotMakeTheProgressGoNegative() {
        let first = playback(position: 30, duration: 120, advancing: true)
        XCTAssertEqual(first.position(at: date.addingTimeInterval(-20)), 30)
        let afterClockChange = MixtapeWidgetPlayback(videoID: "track", position: 30, duration: 120,
            sampledAt: date.addingTimeInterval(-20), isAdvancing: true)
        XCTAssertTrue(afterClockChange.needsPublication(after: first))
    }

    func testRepeatedExplicitPlayAndPauseActionsAreIdempotent() {
        XCTAssertTrue(MixtapeWidgetPlaybackAction.play.shouldChange(isPlaying: false))
        XCTAssertFalse(MixtapeWidgetPlaybackAction.play.shouldChange(isPlaying: true))
        XCTAssertTrue(MixtapeWidgetPlaybackAction.pause.shouldChange(isPlaying: true))
        XCTAssertFalse(MixtapeWidgetPlaybackAction.pause.shouldChange(isPlaying: false))
    }

    func testVersion46SnapshotStillDecodesWithoutAppearanceOrPlaybackFields() throws {
        let legacy = Data(#"{"isPlaying":false,"recentSongs":[],"playlists":[],"updatedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(MixtapeWidgetSnapshot.self, from: legacy)
        XCTAssertNil(decoded.playback)
        XCTAssertNil(decoded.appearance)
    }

    func testPlaybackAndChosenAppearanceRoundTripThroughTheKeychainPayload() throws {
        var snapshot = MixtapeWidgetSnapshot.empty
        snapshot.playback = playback(position: 45, duration: 120, advancing: false)
        snapshot.appearance = MixtapeAppearance.dark.rawValue
        let data = try MixtapeWidgetKeychain.encode(.init(snapshot: snapshot, artwork: [:]))
        let loaded = try MixtapeWidgetKeychain.decode(data).snapshot
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.playback?.position(at: date.addingTimeInterval(500)), 45)
        XCTAssertEqual(loaded.appearance, "dark")
    }

    private func playback(position: Double, duration: Double?, advancing: Bool) -> MixtapeWidgetPlayback {
        .init(videoID: "track", position: position, duration: duration, sampledAt: date, isAdvancing: advancing)
    }
}
