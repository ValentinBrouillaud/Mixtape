import Foundation
import XCTest
@testable import NativeAudioTransport

final class AudioDurationPolicyTests: XCTestCase {
    private func scan(duration: Double, signalEnd: Double?) -> DownloadedAudioProcessor.Scan {
        .init(frames: Int64(duration * 44_100), sampleRate: 44_100, channels: 2,
              lastSignalFrame: signalEnd.map { Int64($0 * 44_100) })
    }

    func testMinutesOfTrailingSilenceAreRemovedWithoutDependingOnMetadata() {
        let reading = scan(duration: 360, signalEnd: 180)
        let target = DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 360)
        XCTAssertEqual(Double(target!) / reading.sampleRate, 180.2, accuracy: 0.0001)
    }

    func testNormalShortEndPaddingIsRetained() {
        XCTAssertNil(DownloadedAudioProcessor.targetFrames(for: scan(duration: 181, signalEnd: 180), reportedDuration: 181))
    }

    func testVeryLongTracksDoNotRequireAnArbitraryPercentageOfSilence() {
        let reading = scan(duration: 3720, signalEnd: 3600)
        let target = DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 3720)
        XCTAssertEqual(Double(target!) / reading.sampleRate, 3600.2, accuracy: 0.0001)
    }

    func testLaterAudioIsRetainedAfterInternalSilence() {
        let reading = scan(duration: 360, signalEnd: 359.8)
        XCTAssertNil(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 360))
    }

    func testPhantomContainerDurationIsRebuiltFromDecodedFrames() {
        let reading = scan(duration: 180, signalEnd: 180)
        XCTAssertEqual(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 360), reading.frames)
        XCTAssertEqual(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 120), reading.frames)
    }

    func testInvalidContainerDurationDoesNotBecomeAClipEndpoint() {
        let reading = scan(duration: 180, signalEnd: 180)
        for reported: Double? in [nil, .nan, .infinity, -3, 0] {
            XCTAssertEqual(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: reported), reading.frames)
        }
    }

    func testEntirelySilentContentDoesNotBecomeAnEmptyFile() {
        let reading = scan(duration: 180, signalEnd: nil)
        XCTAssertNil(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 180))
        XCTAssertEqual(DownloadedAudioProcessor.targetFrames(for: reading, reportedDuration: 360), reading.frames)
    }
}
