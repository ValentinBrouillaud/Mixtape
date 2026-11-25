import Foundation

/// Provisioning profiles are an implementation detail, not an entitlement API
/// (Apple TN3125). The optional XML extraction below only suggests group names;
/// it neither validates CMS signatures nor grants access. Unknown formats fall
/// back to explicit configuration and the historical identifier. The sandbox's
/// containerURL check is always required before a suggestion can be used.
nonisolated enum MixtapeWidgetGroupResolver {
    static let maximumProfileBytes = 2 * 1024 * 1024

    static func isValidIdentifier(_ identifier: String) -> Bool {
        let bytes = Array(identifier.utf8)
        guard identifier.hasPrefix("group."), bytes.count > 6, bytes.count <= 255 else { return false }
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty }) else { return false }
        return bytes.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 46
        }
    }

    static func candidates(explicitIdentifier: String?, provisionedGroups: [String]) -> [String] {
        var groups = Set(provisionedGroups.filter(isValidIdentifier))
        var proposed: [String] = []
        if let explicitIdentifier, isValidIdentifier(explicitIdentifier) { proposed.append(explicitIdentifier) }
        // Sort to keep both processes deterministic if a profile lists multiple
        // Mixtape groups in a different order. Prefer the existing data group.
        if groups.remove(MixtapeWidgetStorage.appGroup) != nil { proposed.append(MixtapeWidgetStorage.appGroup) }
        proposed += groups.filter { $0.lowercased().contains("mixtape") }.sorted()
        let concrete = Set(provisionedGroups.filter(isValidIdentifier))
        if concrete.count == 1, let only = concrete.first { proposed.append(only) }
        // Multiple unrelated groups are ambiguous. Never select one at random.
        proposed.append(MixtapeWidgetStorage.appGroup)
        var seen = Set<String>()
        return proposed.filter { seen.insert($0).inserted }
    }

    static func provisionedGroups(from profile: Data) -> [String] {
        guard !profile.isEmpty, profile.count <= maximumProfileBytes else { return [] }
        // Accept a plain plist fixture or a future non-CMS plist representation.
        if let groups = groups(inPlist: profile) { return groups }
        // Today's embedded.mobileprovision is CMS-wrapped XML. Extract at most
        // one bounded plist, without treating the surrounding CMS as trusted.
        guard let start = profile.range(of: Data("<plist".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex) else { return [] }
        return groups(inPlist: profile.subdata(in: start.lowerBound..<end.upperBound)) ?? []
    }

    private static func groups(inPlist data: Data) -> [String]? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return nil }
        return groups.filter(isValidIdentifier)
    }
}
