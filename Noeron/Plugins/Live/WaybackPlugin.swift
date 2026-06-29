//
//  WaybackPlugin.swift
//  Noeron
//
//  Wayback Machine (Internet Archive CDX API, keyless, like waybackurls / gau):
//  archived snapshots for a domain — first/last capture dates and sample URLs.
//

import Foundation

struct WaybackPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "wayback",
            name: "Wayback Machine",
            summary: "Archived snapshots for a domain via the Internet Archive CDX API: first/last capture dates and a sample of archived URLs. Keyless (like waybackurls / gau).",
            category: .network,
            acceptedKinds: [.domain, .url],
            producesKinds: [.url],
            requiresAPIKey: false,
            docURL: "https://github.com/internetarchive/wayback",
            isLive: true,
            symbol: "clock.arrow.circlepath"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let target = entity.kind == .url ? entity.label : WhoisPlugin.normalize(entity.label)
        var comps = URLComponents(string: "http://web.archive.org/cdx/search/cdx")!
        comps.queryItems = [
            .init(name: "url", value: entity.kind == .url ? target : "\(target)/*"),
            .init(name: "matchType", value: entity.kind == .url ? "exact" : "domain"),
            .init(name: "fl", value: "timestamp,original"),
            .init(name: "collapse", value: "urlkey"),
            .init(name: "limit", value: "300"),
            .init(name: "output", value: "json")
        ]
        guard let url = comps.url else { throw PluginError.unsupportedEntity }
        let rows = (try? await context.getJSON([[String]].self, from: url)) ?? []
        // First row is the CDX header.
        let data = rows.dropFirst().filter { $0.count >= 2 }
        guard !data.isEmpty else { return PluginResult(rawExcerpt: "No Wayback snapshots for \(target)") }

        var result = PluginResult(rawExcerpt: "Wayback: \(data.count) archived URLs for \(target)")
        result.inputAttributes.append(.init(key: "Archived URLs", value: String(data.count), kind: .number, source: "Wayback Machine"))

        let timestamps = data.map { $0[0] }.sorted()
        if let first = timestamps.first, let d = Self.cdxDate(first) {
            result.events.append(.init(title: "First Wayback capture: \(target)", date: d, category: "Archive"))
        }
        if let last = timestamps.last, let d = Self.cdxDate(last) {
            result.events.append(.init(title: "Last Wayback capture: \(target)", date: d, category: "Archive"))
        }
        // A handful of distinct archived URLs as pivots.
        for row in data.prefix(12) {
            let ts = row[0], original = row[1]
            result.entities.append(.init(
                kind: .url, label: original, subtitle: "Archived snapshot",
                confidence: 0.5, sourceURL: "https://web.archive.org/web/\(ts)/\(original)",
                linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        return result
    }

    static func cdxDate(_ ts: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMddHHmmss"
        return f.date(from: ts) ?? { let g = DateFormatter(); g.dateFormat = "yyyyMMdd"; return g.date(from: String(ts.prefix(8))) }()
    }
}
