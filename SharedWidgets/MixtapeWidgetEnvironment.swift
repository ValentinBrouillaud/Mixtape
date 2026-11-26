import Foundation

nonisolated enum MixtapeWidgetConfigurationIssue: String, Sendable {
    case missingExtension, conflictingIdentifiers, noCommonMixtapeGroup
}

/// Inspects both installed bundles, including after a sideloading tool has
/// replaced their profiles. Only the OS can authorize a candidate container;
/// only a receipt written by the extension proves it read the snapshot.
nonisolated struct MixtapeWidgetEnvironment: Sendable {
    let appIdentifier: String?
    let widgetIdentifier: String?
    let appProfile: MixtapeWidgetGroupResolver.Profile?
    let widgetProfile: MixtapeWidgetGroupResolver.Profile?
    let candidates: [String]
    let issue: MixtapeWidgetConfigurationIssue?

    static func inspect(bundleURL: URL) -> Self {
        let app = bundleURL.pathExtension == "appex"
            ? bundleURL.deletingLastPathComponent().deletingLastPathComponent() : bundleURL
        let widget = app.appendingPathComponent("PlugIns/MixtapeWidgets.appex", isDirectory: true)
        let appInfo = plist(at: app.appendingPathComponent("Info.plist")) ?? [:]
        let widgetInfo = plist(at: widget.appendingPathComponent("Info.plist"))
        let appProfile = profile(at: app)
        let widgetProfile = profile(at: widget)
        let appGroup = appInfo["MixtapeAppGroupIdentifier"] as? String
        let widgetGroup = widgetInfo?["MixtapeAppGroupIdentifier"] as? String
        let candidates = MixtapeWidgetGroupResolver.sharedCandidates(
            explicitIdentifier: appGroup ?? widgetGroup, app: appProfile, widget: widgetProfile
        )
        let issue: MixtapeWidgetConfigurationIssue?
        if widgetInfo == nil {
            issue = .missingExtension
        } else if let appGroup, let widgetGroup, appGroup != widgetGroup {
            issue = .conflictingIdentifiers
        } else if candidates.isEmpty {
            issue = .noCommonMixtapeGroup
        } else {
            issue = nil
        }
        return Self(
            appIdentifier: appInfo["CFBundleIdentifier"] as? String,
            widgetIdentifier: widgetInfo?["CFBundleIdentifier"] as? String,
            appProfile: appProfile, widgetProfile: widgetProfile,
            candidates: issue == nil ? candidates : [], issue: issue
        )
    }

    private static func profile(at bundle: URL) -> MixtapeWidgetGroupResolver.Profile? {
        guard let data = smallFile(at: bundle.appendingPathComponent("embedded.mobileprovision")) else { return nil }
        return MixtapeWidgetGroupResolver.profile(from: data)
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = smallFile(at: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private static func smallFile(at url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        let limit = MixtapeWidgetGroupResolver.maximumProfileBytes
        guard let data = try? file.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
}
