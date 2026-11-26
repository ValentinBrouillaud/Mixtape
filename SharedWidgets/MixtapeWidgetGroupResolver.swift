import Foundation

/// Provisioning profiles are an implementation detail, not an entitlement API
/// (Apple TN3125). The optional XML extraction below only suggests group names;
/// it neither validates CMS signatures nor grants access. Unknown formats fall
/// back to explicit configuration and the historical identifier. The sandbox's
/// containerURL check is always required before a suggestion can be used.
nonisolated enum MixtapeWidgetGroupResolver {
    static let maximumProfileBytes = 2 * 1024 * 1024

    struct Profile: Equatable, Sendable {
        let applicationIdentifier: String?
        let teamIdentifier: String?
        let groups: [String]
        var keychainGroups: [String] = []
        var appIdentifierPrefix: String? = nil

        func permits(_ identifier: String) -> Bool {
            groups.contains { group in
                group == identifier || (group.hasSuffix(".*") && identifier.hasPrefix(String(group.dropLast())))
            }
        }
    }

    static func isValidIdentifier(_ identifier: String) -> Bool {
        let bytes = Array(identifier.utf8)
        guard identifier.hasPrefix("group."), bytes.count > 6, bytes.count <= 255 else { return false }
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty }) else { return false }
        return bytes.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 46
        }
    }

    static func candidates(explicitIdentifier: String?, provisionedGroups: [String], teamIdentifiers: [String] = []) -> [String] {
        var groups = Set(provisionedGroups.filter { isValidIdentifier($0) && isMixtapeGroup($0) })
        var proposed: [String] = []
        if let explicitIdentifier, isValidIdentifier(explicitIdentifier) { proposed.append(explicitIdentifier) }
        // Sort to keep both processes deterministic if a profile lists multiple
        // Mixtape groups in a different order. Prefer the existing data group.
        if groups.remove(MixtapeWidgetStorage.appGroup) != nil { proposed.append(MixtapeWidgetStorage.appGroup) }
        proposed += groups.sorted()
        // Re-signers commonly append the personal team's identifier. Both
        // processes derive the same hints, then still ask the OS for access.
        proposed += Set(teamIdentifiers.filter(isValidTeamIdentifier)).sorted().map { MixtapeWidgetStorage.appGroup + "." + $0 }
        // A sole unrelated group (for example SideStore's) is not Mixtape's
        // shared store. Never publish listening history into that container.
        proposed.append(MixtapeWidgetStorage.appGroup)
        var seen = Set<String>()
        return proposed.filter { seen.insert($0).inserted }
    }

    static func sharedCandidates(explicitIdentifier: String?, app: Profile?, widget: Profile?) -> [String] {
        candidates(
            explicitIdentifier: explicitIdentifier,
            provisionedGroups: (app?.groups ?? []) + (widget?.groups ?? []),
            teamIdentifiers: [app?.teamIdentifier, widget?.teamIdentifier].compactMap { $0 }
        ).filter { identifier in
            // A readable profile without App Groups is different from an
            // unknown profile format. Suggestions must be compatible with BOTH
            // installed bundles. A profile is still not proof of sandbox access.
            (app?.permits(identifier) ?? true) && (widget?.permits(identifier) ?? true)
        }
    }

    private static func isMixtapeGroup(_ identifier: String) -> Bool {
        identifier.split(separator: ".").contains { $0.lowercased() == "mixtape" }
    }

    private static func isValidTeamIdentifier(_ identifier: String) -> Bool {
        identifier.utf8.count == 10 && identifier.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }

    static func provisionedGroups(from profile: Data) -> [String] {
        self.profile(from: profile)?.groups.filter(isValidIdentifier) ?? []
    }

    static func profile(from data: Data) -> Profile? {
        guard !data.isEmpty, data.count <= maximumProfileBytes else { return nil }
        // Accept a plain plist fixture or a future non-CMS plist representation.
        if let profile = profile(inPlist: data) { return profile }
        // Today's embedded.mobileprovision is CMS-wrapped XML. Extract at most
        // one bounded plist, without treating the surrounding CMS as trusted.
        guard let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        return profile(inPlist: data.subdata(in: start.lowerBound..<end.upperBound))
    }

    private static func profile(inPlist data: Data) -> Profile? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else { return nil }
        let groups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        let team = (entitlements["com.apple.developer.team-identifier"] as? String)
            ?? (root["TeamIdentifier"] as? [String])?.first
        return Profile(
            applicationIdentifier: entitlements["application-identifier"] as? String,
            teamIdentifier: team.flatMap { isValidTeamIdentifier($0) ? $0 : nil },
            groups: groups.filter { isValidIdentifier($0) || $0 == "group.*" || ($0.hasSuffix(".*") && isValidIdentifier(String($0.dropLast(2)))) },
            keychainGroups: entitlements["keychain-access-groups"] as? [String] ?? [],
            appIdentifierPrefix: (root["ApplicationIdentifierPrefix"] as? [String])?.first.flatMap { isValidTeamIdentifier($0) ? $0 : nil }
        )
    }
}
