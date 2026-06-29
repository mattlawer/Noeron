//
//  WikidataPlugin.swift
//  Noeron
//
//  Wikidata (keyless): official website, inception date and identifiers for people
//  and organisations.
//

import Foundation

struct WikidataPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "wikidata", name: "Wikidata",
              summary: "Official website, inception date and identifiers for people and organisations.",
              category: .knowledge, acceptedKinds: [.person, .company, .organization],
              producesKinds: [.domain],
              requiresAPIKey: false,
              docURL: "https://www.wikidata.org/wiki/Wikidata:Data_access", isLive: true, symbol: "globe.americas")
    }

    private struct Search: Decodable {
        let search: [Hit]?
        struct Hit: Decodable { let id: String?; let label: String?; let description: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        var comps = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "wbsearchentities"), .init(name: "search", value: entity.label),
            .init(name: "language", value: "en"), .init(name: "format", value: "json"),
            .init(name: "type", value: "item"), .init(name: "limit", value: "1")
        ]
        let search = try await context.getJSON(Search.self, from: comps.url!)
        guard let hit = search.search?.first, let qid = hit.id else { return .empty }

        var result = PluginResult(rawExcerpt: "Wikidata \(qid): \(hit.description ?? "")")
        result.inputAttributes.append(.init(key: "Wikidata", value: qid, source: "Wikidata"))
        if let desc = hit.description { result.inputAttributes.append(.init(key: "Description", value: desc, source: "Wikidata")) }

        // Fetch claims and pull official website (P856) + inception (P571).
        let (data, _) = try await context.get(URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json")!)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entities = json["entities"] as? [String: Any],
           let ent = entities[qid] as? [String: Any],
           let claims = ent["claims"] as? [String: Any] {

            if let site = Self.stringClaim(claims, "P856"),
               let host = URL(string: site)?.host {
                result.entities.append(.init(kind: .domain, label: host.lowercased(), subtitle: "Official website",
                                             confidence: 0.8, sourceURL: site, linkKind: .relatedTo, linkDirection: .fromInput))
            }
            if let time = Self.timeClaim(claims, "P571"), let d = ISO8601Date.parse(String(time.dropFirst())) {
                result.events.append(.init(title: "Founded: \(hit.label ?? entity.label)", date: d, precision: .year, category: "Corporate"))
            }
        }
        return result
    }

    /// Extract a string-valued claim (e.g. URL) by property id.
    private static func stringClaim(_ claims: [String: Any], _ pid: String) -> String? {
        guard let arr = claims[pid] as? [[String: Any]], let first = arr.first,
              let snak = first["mainsnak"] as? [String: Any],
              let dv = snak["datavalue"] as? [String: Any] else { return nil }
        return dv["value"] as? String
    }

    /// Extract a time-valued claim (returns the raw "+yyyy-MM-..." string).
    private static func timeClaim(_ claims: [String: Any], _ pid: String) -> String? {
        guard let arr = claims[pid] as? [[String: Any]], let first = arr.first,
              let snak = first["mainsnak"] as? [String: Any],
              let dv = snak["datavalue"] as? [String: Any],
              let value = dv["value"] as? [String: Any] else { return nil }
        return value["time"] as? String
    }
}
