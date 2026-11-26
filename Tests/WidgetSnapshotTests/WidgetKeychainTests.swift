import Foundation
import CoreGraphics
import ImageIO
import Security
import XCTest
@testable import SharedWidgetModel

final class WidgetKeychainTests: XCTestCase {
    func testMetadataAndArtworkRoundTripWithoutAudioOrAccountData() throws {
        let payload = payload(title: "Received title", updatedAt: 100)
        XCTAssertEqual(try MixtapeWidgetKeychain.decode(MixtapeWidgetKeychain.encode(payload)), payload)
    }

    func testUnknownVersionsAndUnsafeArtworkNamesAreRejected() throws {
        let good = payload(title: "Title", updatedAt: 100)
        var future = good
        future.version = 2
        XCTAssertThrowsError(try MixtapeWidgetKeychain.encode(future))
        XCTAssertThrowsError(try MixtapeWidgetKeychain.decode(JSONEncoder().encode(future)))
        for name in ["../cover.jpg", "/cover.jpg", "..", ".", ""] {
            let bad = MixtapeWidgetKeychain.Payload(snapshot: good.snapshot, artwork: [name: Data([1])])
            XCTAssertThrowsError(try MixtapeWidgetKeychain.encode(bad))
            XCTAssertThrowsError(try MixtapeWidgetKeychain.decode(JSONEncoder().encode(bad)))
        }
    }

    func testOversizedPayloadAndArtworkAreRejectedBeforeCaching() throws {
        XCTAssertThrowsError(try MixtapeWidgetKeychain.decode(Data(repeating: 32, count: MixtapeWidgetKeychain.maximumPayloadBytes + 1)))
        let good = payload(title: "Title", updatedAt: 100)
        let oversized = MixtapeWidgetKeychain.Payload(snapshot: good.snapshot,
            artwork: ["cover.jpg": Data(repeating: 1, count: MixtapeWidgetKeychain.maximumArtworkBytes + 1)])
        XCTAssertThrowsError(try MixtapeWidgetKeychain.encode(oversized))
        let many = MixtapeWidgetKeychain.Payload(snapshot: good.snapshot,
            artwork: Dictionary(uniqueKeysWithValues: (0...MixtapeWidgetKeychain.maximumArtworkCount).map { ("\($0).jpg", Data([1])) }))
        XCTAssertThrowsError(try MixtapeWidgetKeychain.encode(many))
    }

    func testDeniedGroupsAreSkippedAndOnlySuccessfulWriteIsReported() throws {
        let first = MixtapeWidgetKeychain.Candidate(group: "A1B2C3D4E5.com.alexcding.mixtape.widgets.shared")
        let second = MixtapeWidgetKeychain.Candidate(group: nil)
        var tried: [MixtapeWidgetKeychain.Candidate] = []
        let result = try MixtapeWidgetKeychain.publish(candidates: [first, second]) { candidate in
            tried.append(candidate)
            return candidate == first ? errSecMissingEntitlement : errSecSuccess
        }
        XCTAssertEqual(tried, [first, second])
        XCTAssertEqual(result, second.identifier)
    }

    func testFailureToWriteAnyGroupDoesNotClaimSuccessfulPublication() {
        XCTAssertThrowsError(try MixtapeWidgetKeychain.publish(candidates: [.init(group: nil)]) { _ in errSecMissingEntitlement })
        XCTAssertThrowsError(try MixtapeWidgetKeychain.publish(candidates: []) { _ in XCTFail("Unexpected write"); return errSecSuccess })
    }

    func testWidgetReadChoosesNewestValidSnapshotAcrossAuthorizedCandidates() throws {
        let old = try MixtapeWidgetKeychain.encode(payload(title: "Old title", updatedAt: 100))
        let fresh = try MixtapeWidgetKeychain.encode(payload(title: "Current title", updatedAt: 200))
        let candidates = [MixtapeWidgetKeychain.Candidate(group: "old"), .init(group: "new"), .init(group: nil)]
        let result = MixtapeWidgetKeychain.load(candidates: candidates) { candidate in
            switch candidate.group {
            case "old": (errSecSuccess, old)
            case "new": (errSecSuccess, fresh)
            default: (errSecMissingEntitlement, nil)
            }
        }
        XCTAssertEqual(result.0.snapshot.currentSong?.title, "Current title")
        XCTAssertNil(result.0.issue)
        XCTAssertEqual(result.0.sharedIdentifier, candidates[1].identifier)
    }

    func testCorruptCopyCannotHideValidMetadataInAnotherAuthorizedGroup() throws {
        let valid = try MixtapeWidgetKeychain.encode(payload(title: "Valid title", updatedAt: 100))
        let result = MixtapeWidgetKeychain.load(candidates: [.init(group: "bad"), .init(group: nil)]) {
            (errSecSuccess, $0.group == nil ? valid : Data("broken".utf8))
        }
        XCTAssertEqual(result.0.snapshot.currentSong?.title, "Valid title")
        XCTAssertNil(result.0.issue)
    }

    func testUnavailableMissingAndCorruptDataRemainDistinct() {
        let candidates = [MixtapeWidgetKeychain.Candidate(group: nil)]
        XCTAssertEqual(MixtapeWidgetKeychain.load(candidates: candidates) { _ in (errSecMissingEntitlement, nil) }.0.issue, .sharedContainerUnavailable)
        XCTAssertEqual(MixtapeWidgetKeychain.load(candidates: candidates) { _ in (errSecItemNotFound, nil) }.0.issue, .noSnapshot)
        XCTAssertEqual(MixtapeWidgetKeychain.load(candidates: candidates) { _ in (errSecSuccess, Data()) }.0.issue, .unreadableSnapshot)
    }

    func testSideloadProfileOnlyProducesOwnTeamAndMixtapeKeychainHints() {
        let profile = MixtapeWidgetGroupResolver.Profile(applicationIdentifier: nil, teamIdentifier: "A1B2C3D4E5", groups: [], keychainGroups: ["A1B2C3D4E5.*"])
        let environment = environment(app: profile, widget: nil)
        let candidates = MixtapeWidgetKeychain.candidates(in: environment)
        XCTAssertEqual(candidates.map(\.group), [
            "A1B2C3D4E5.com.alexcding.mixtape.widgets.shared",
            "A1B2C3D4E5.com.alexcding.mixtape.A1B2C3D4E5",
            "A1B2C3D4E5.*", nil,
        ])
        XCTAssertFalse(candidates.contains { $0.identifier.contains("SideStore") })
    }

    func testDifferentTeamsMissingIdentityOrMissingWidgetDoNotInventSharedKeychain() {
        let app = MixtapeWidgetGroupResolver.Profile(applicationIdentifier: nil, teamIdentifier: "A1B2C3D4E5", groups: [])
        let widget = MixtapeWidgetGroupResolver.Profile(applicationIdentifier: nil, teamIdentifier: "Z9Y8X7W6V5", groups: [])
        XCTAssertEqual(MixtapeWidgetKeychain.candidates(in: environment(app: app, widget: widget)), [])
        XCTAssertEqual(MixtapeWidgetKeychain.candidates(in: environment(app: nil, widget: nil)), [])
        let missing = MixtapeWidgetEnvironment(appIdentifier: "com.alexcding.mixtape", widgetIdentifier: nil, appProfile: app, widgetProfile: nil, candidates: [], issue: .missingExtension)
        XCTAssertEqual(MixtapeWidgetKeychain.candidates(in: missing), [])
    }

    func testKeychainHintsUseTheAppIdentifierPrefixWhenItDiffersFromTeamIdentity() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "TeamIdentifier": ["A1B2C3D4E5"], "ApplicationIdentifierPrefix": ["Z9Y8X7W6V5"],
            "Entitlements": ["keychain-access-groups": ["Z9Y8X7W6V5.*"]],
        ], format: .binary, options: 0)
        let profile = try XCTUnwrap(MixtapeWidgetGroupResolver.profile(from: data))
        let candidates = MixtapeWidgetKeychain.candidates(in: environment(app: profile, widget: profile))
        XCTAssertEqual(candidates.first?.group, "Z9Y8X7W6V5.com.alexcding.mixtape.widgets.shared")
        XCTAssertTrue(candidates.contains { $0.group == "Z9Y8X7W6V5.*" })
        XCTAssertFalse(candidates.contains { $0.group?.hasPrefix("A1B2C3D4E5.") == true })
    }

    func testLargeCachedArtworkBecomesSmallJPEGForTheWidget() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 512, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
        let original = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixtape-widget-art-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try XCTUnwrap(MixtapeWidgetKeychain.thumbnail(at: url))
        XCTAssertLessThanOrEqual(thumbnail.count, MixtapeWidgetKeychain.maximumArtworkBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 192)
        XCTAssertEqual(image.height, 96)
    }

    private func payload(title: String, updatedAt: TimeInterval) -> MixtapeWidgetKeychain.Payload {
        let song = MixtapeWidgetSong(videoId: "video", title: title, artist: "Artist", artworkFileName: "cover.jpg")
        return .init(snapshot: .init(currentSong: song, isPlaying: false, recentSongs: [song],
            playlists: [.init(id: "playlist", title: "Favorite", songCount: 8)], updatedAt: Date(timeIntervalSince1970: updatedAt)),
            artwork: ["cover.jpg": Data([1, 2, 3])])
    }

    private func environment(app: MixtapeWidgetGroupResolver.Profile?, widget: MixtapeWidgetGroupResolver.Profile?) -> MixtapeWidgetEnvironment {
        .init(appIdentifier: "com.alexcding.mixtape.A1B2C3D4E5", widgetIdentifier: "com.alexcding.mixtape.A1B2C3D4E5.widgets",
            appProfile: app, widgetProfile: widget, candidates: [], issue: .noCommonMixtapeGroup)
    }
}
