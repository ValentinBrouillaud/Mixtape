import Foundation
import XCTest
@testable import SharedWidgetModel

final class WidgetGroupResolverTests: XCTestCase {
    func testExplicitBuildConfigurationTakesPriorityOverProfileSuggestions() {
        let groups = MixtapeWidgetGroupResolver.candidates(
            explicitIdentifier: "group.personal.music", provisionedGroups: [MixtapeWidgetStorage.appGroup]
        )
        XCTAssertEqual(groups.first, "group.personal.music")
        XCTAssertEqual(groups.last, MixtapeWidgetStorage.appGroup)
    }

    func testRenamedMixtapeGroupIsPreferredToUnrelatedGroups() {
        let groups = MixtapeWidgetGroupResolver.candidates(
            explicitIdentifier: nil,
            provisionedGroups: ["group.other.product", "group.personal.Mixtape.ABC123", "group.another.product"]
        )
        XCTAssertEqual(groups, ["group.personal.Mixtape.ABC123", MixtapeWidgetStorage.appGroup])
    }

    func testSingleCompletelyRenamedConcreteGroupCanBeTried() {
        XCTAssertEqual(MixtapeWidgetGroupResolver.candidates(
            explicitIdentifier: nil, provisionedGroups: ["group.resigned.shared"]
        ), ["group.resigned.shared", MixtapeWidgetStorage.appGroup])
    }

    func testMultipleUnrelatedGroupsAreNotSelectedArbitrarily() {
        XCTAssertEqual(MixtapeWidgetGroupResolver.candidates(
            explicitIdentifier: nil, provisionedGroups: ["group.one.shared", "group.two.shared"]
        ), [MixtapeWidgetStorage.appGroup])
    }

    func testCandidateOrderIsConsistentAcrossProfileOrderingAndDuplicates() {
        let input = ["group.z.Mixtape", "group.a.Mixtape", MixtapeWidgetStorage.appGroup, "group.z.Mixtape"]
        let first = MixtapeWidgetGroupResolver.candidates(explicitIdentifier: nil, provisionedGroups: input)
        let second = MixtapeWidgetGroupResolver.candidates(explicitIdentifier: nil, provisionedGroups: Array(input.reversed()))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, [MixtapeWidgetStorage.appGroup, "group.a.Mixtape", "group.z.Mixtape"])
    }

    func testWildcardsPathsAndInvalidNamesNeverBecomeContainerCandidates() {
        let invalid = ["*", "group.*", "group.", "group..music", "group/mixtape", "../group.mixtape", "group.my music", "group.my_music", "not-a-group"]
        for value in invalid { XCTAssertFalse(MixtapeWidgetGroupResolver.isValidIdentifier(value), value) }
        XCTAssertEqual(MixtapeWidgetGroupResolver.candidates(
            explicitIdentifier: "group.*", provisionedGroups: invalid
        ), [MixtapeWidgetStorage.appGroup])
    }

    func testPlainAndCMSWrappedXMLProfilesSuggestTheSameConcreteGroups() throws {
        let xml = try profileXML(groups: ["group.personal.Mixtape", "group.*", "group.other.music"])
        var wrapped = Data([0x30, 0x82, 0x00, 0xff, 0x06, 0x09])
        wrapped.append(xml)
        wrapped.append(Data([0x00, 0x31, 0x82, 0x00, 0x0f]))
        let expected = ["group.personal.Mixtape", "group.other.music"]
        XCTAssertEqual(MixtapeWidgetGroupResolver.provisionedGroups(from: xml), expected)
        XCTAssertEqual(MixtapeWidgetGroupResolver.provisionedGroups(from: wrapped), expected)
    }

    func testUnknownAbsentAndOversizedProfilesKeepTheStableFallback() throws {
        let invalidProfiles = [Data(), Data([0x30, 0x80, 0x00, 0x00]), Data("<plist><dict>broken".utf8), Data(repeating: 0, count: MixtapeWidgetGroupResolver.maximumProfileBytes + 1)]
        for profile in invalidProfiles {
            let groups = MixtapeWidgetGroupResolver.provisionedGroups(from: profile)
            XCTAssertEqual(groups, [])
            XCTAssertEqual(MixtapeWidgetGroupResolver.candidates(explicitIdentifier: nil, provisionedGroups: groups), [MixtapeWidgetStorage.appGroup])
        }
    }

    private func profileXML(groups: [String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "Name": "Test profile name",
            "Entitlements": ["com.apple.security.application-groups": groups],
        ], format: .xml, options: 0)
    }
}
