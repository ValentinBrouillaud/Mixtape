import Foundation
import XCTest
@testable import SharedWidgetModel

final class WidgetEnvironmentTests: XCTestCase {
    func testAppAndWidgetReadBothInstalledProfilesAndChooseTheSameCommonGroup() throws {
        try withApp { app, widget in
            let common = MixtapeWidgetStorage.appGroup + ".A1B2C3D4E5"
            try writeProfile([MixtapeWidgetStorage.appGroup, common, "group.com.SideStore.SideStore.A1B2C3D4E5"], in: app)
            try writeProfile([common], in: widget)
            let hostResult = MixtapeWidgetEnvironment.inspect(bundleURL: app)
            let widgetResult = MixtapeWidgetEnvironment.inspect(bundleURL: widget)
            XCTAssertEqual(hostResult.candidates, [common])
            XCTAssertEqual(widgetResult.candidates, hostResult.candidates)
            XCTAssertEqual(widgetResult.appProfile, hostResult.appProfile)
            XCTAssertEqual(widgetResult.widgetProfile, hostResult.widgetProfile)
            XCTAssertEqual(hostResult.widgetIdentifier, "com.example.mixtape.widgets")
            XCTAssertNil(hostResult.issue)
        }
    }

    func testReportedSideStoreGroupAndWidgetWithoutCapabilityExplainTheFailure() throws {
        try withApp { app, widget in
            try writeProfile(["group.com.SideStore.SideStore.A1B2C3D4E5"], in: app)
            try writeProfile([], in: widget)
            let result = MixtapeWidgetEnvironment.inspect(bundleURL: app)
            XCTAssertEqual(result.issue, .noCommonMixtapeGroup)
            XCTAssertEqual(result.candidates, [])
            XCTAssertEqual(result.appProfile?.groups, ["group.com.SideStore.SideStore.A1B2C3D4E5"])
            XCTAssertEqual(result.widgetProfile?.groups, [])
        }
    }

    func testMissingExtensionCannotBeReportedAsWorkingSharing() throws {
        try withApp { app, widget in
            try FileManager.default.removeItem(at: widget)
            let result = MixtapeWidgetEnvironment.inspect(bundleURL: app)
            XCTAssertEqual(result.issue, .missingExtension)
            XCTAssertEqual(result.candidates, [])
            XCTAssertNil(result.widgetIdentifier)
        }
    }

    func testUnknownProfileFormatPreservesOSCheckedFallback() throws {
        try withApp { app, widget in
            try Data("future profile format".utf8).write(to: widget.appendingPathComponent("embedded.mobileprovision"))
            let result = MixtapeWidgetEnvironment.inspect(bundleURL: app)
            XCTAssertNil(result.issue)
            XCTAssertNil(result.widgetProfile)
            XCTAssertEqual(result.candidates, [MixtapeWidgetStorage.appGroup])
        }
    }

    func testConflictingExplicitGroupsCannotSplitTheTwoProcesses() throws {
        try withApp { app, widget in
            try writeInfo("com.example.mixtape", group: "group.custom.music", in: app)
            try writeInfo("com.example.mixtape.widgets", group: "group.different.music", in: widget)
            let result = MixtapeWidgetEnvironment.inspect(bundleURL: app)
            XCTAssertEqual(result.issue, .conflictingIdentifiers)
            XCTAssertEqual(result.candidates, [])
        }
    }

    private func withApp(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mixtape-widget-environment-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("Mixtape.app", isDirectory: true)
        let widget = app.appendingPathComponent("PlugIns/MixtapeWidgets.appex", isDirectory: true)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeInfo("com.example.mixtape", in: app)
        try writeInfo("com.example.mixtape.widgets", in: widget)
        try body(app, widget)
    }

    private func writeInfo(_ identifier: String, group: String? = nil, in bundle: URL) throws {
        var info = ["CFBundleIdentifier": identifier]
        info["MixtapeAppGroupIdentifier"] = group
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Info.plist"))
    }

    private func writeProfile(_ groups: [String], in bundle: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: [
            "TeamIdentifier": ["A1B2C3D4E5"],
            "Entitlements": ["com.apple.security.application-groups": groups],
        ], format: .xml, options: 0).write(to: bundle.appendingPathComponent("embedded.mobileprovision"))
    }
}
