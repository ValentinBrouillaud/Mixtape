import Foundation

/// A directory of official playlists, not a locally manufactured ranking.
nonisolated struct RegionalChartDirectory: Sendable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case current, weekly, monthly
        var id: String { rawValue }
    }

    struct Chart: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let period: Period
    }

    let charts: [Chart]

    // Countries documented by YouTube Charts. ZZ is the global chart.
    static let countries = ["ZZ", "AR", "AU", "AT", "BE", "BO", "BR", "CA", "CL", "CO", "CR", "CZ", "DK", "DO", "EC", "EG", "SV", "EE", "FI", "FR", "DE", "GT", "HN", "HK", "HU", "IS", "IN", "ID", "IE", "IL", "IT", "JP", "KE", "LU", "MY", "MX", "NL", "NZ", "NI", "NG", "NO", "PA", "PY", "PE", "PH", "PL", "PT", "RO", "RU", "SA", "RS", "SG", "ZA", "KR", "ES", "SE", "CH", "TW", "TZ", "TH", "TR", "UG", "GB", "UA", "AE", "UY", "US", "VN", "ZW"]

    init(json: [String: Any], periodEvidence: [String: String] = [:]) {
        var found: [Chart] = []
        var seen: Set<String> = []
        func text(_ value: Any?) -> String {
            guard let value = value as? [String: Any] else { return "" }
            if let simple = value["simpleText"] as? String { return simple }
            return (value["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        }
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                if let tile = object["musicTwoRowItemRenderer"] as? [String: Any],
                   let titleObject = tile["title"] as? [String: Any] {
                    let title = text(titleObject)
                    let runs = titleObject["runs"] as? [[String: Any]] ?? []
                    let endpoints = [tile["navigationEndpoint"] as? [String: Any]] + runs.map { $0["navigationEndpoint"] as? [String: Any] }
                    let browseID = endpoints.compactMap { ($0?["browseEndpoint"] as? [String: Any])?["browseId"] as? String }.first
                    if let browseID, browseID.hasPrefix("VLPL"), !title.isEmpty {
                        let id = String(browseID.dropFirst(2))
                        let lower = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                        // Never relabel a daily or unspecified list as weekly.
                        let evidence = (periodEvidence[id] ?? "").lowercased()
                        let weekly = lower.contains("weekly") || lower.contains("hebdo") || lower.contains("semaine") ||
                            evidence.contains("this week's") || evidence.contains("weekly") ||
                            evidence.contains("semaine") || evidence.contains("hebdo")
                        let monthly = lower.contains("monthly") || lower.contains("mensuel") || lower.contains("mois")
                        if !monthly, seen.insert(id).inserted {
                            found.append(Chart(id: id, title: title, period: weekly ? .weekly : .current))
                        }
                    }
                }
                // Arrays preserve the source's order. JSON object key order is irrelevant.
                for key in object.keys.sorted() { if let child = object[key] { visit(child) } }
            } else if let list = value as? [Any] { for child in list { visit(child) } }
        }
        visit(json)
        charts = found
    }

    /// Period evidence must belong to the exact official playlist being ranked.
    /// Some public Top 100 lists omit the period in their title and state it
    /// only in the description shelf.
    static func sourceDescription(in value: Any) -> String {
        if let object = value as? [String: Any] {
            if let shelf = object["musicDescriptionShelfRenderer"] as? [String: Any],
               let description = shelf["description"] as? [String: Any] {
                if let text = description["simpleText"] as? String { return text }
                return (description["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
            }
            return object.keys.sorted().compactMap { object[$0] }.map { sourceDescription(in: $0) }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let array = value as? [Any] { return array.map { sourceDescription(in: $0) }.filter { !$0.isEmpty }.joined(separator: " ") }
        return ""
    }

    func choices(for period: Period) -> [Chart] {
        guard period != .monthly else { return [] }
        return charts.filter { $0.period == period }
    }
}
