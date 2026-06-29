//
//  URLScanPlugin.swift
//  Noeron
//
//  urlscan.io (keyless search API): recent public scans of a domain/IP — scanned
//  URLs and the related domains, IPs and servers observed.
//

import Foundation

struct URLScanPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "urlscan",
            name: "urlscan.io",
            summary: "Recent public scans of a domain/IP via urlscan.io's keyless search API: scanned URLs and the related domains, IPs and servers observed.",
            category: .threat,
            acceptedKinds: [.domain, .ipAddress],
            producesKinds: [.url, .domain, .ipAddress],
            requiresAPIKey: false,
            docURL: "https://urlscan.io/docs/search/",
            isLive: true,
            symbol: "scope"
        )
    }

    private struct Search: Decodable {
        let results: [Res]?
        struct Res: Decodable {
            let task: Task?; let page: Page?; let _id: String?
            struct Task: Decodable { let url: String?; let domain: String? }
            struct Page: Decodable { let domain: String?; let ip: String?; let server: String?; let asnname: String? }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let query = entity.kind == .ipAddress ? "ip:\(entity.label)" : "domain:\(WhoisPlugin.normalize(entity.label))"
        var comps = URLComponents(string: "https://urlscan.io/api/v1/search/")!
        comps.queryItems = [.init(name: "q", value: query), .init(name: "size", value: "20")]
        guard let url = comps.url else { throw PluginError.unsupportedEntity }

        let (data, http) = try await context.get(url)
        guard http.statusCode == 200, let search = try? JSONDecoder().decode(Search.self, from: data) else {
            return PluginResult(rawExcerpt: "urlscan.io HTTP \(http.statusCode)")
        }
        let results = search.results ?? []
        var result = PluginResult(rawExcerpt: "urlscan.io: \(results.count) scans for \(query)")
        var seen = Set<String>()
        for res in results.prefix(15) {
            if let scanURL = res.task?.url, let id = res._id {
                result.entities.append(.init(kind: .url, label: scanURL, subtitle: "urlscan.io scan",
                                             confidence: 0.55, sourceURL: "https://urlscan.io/result/\(id)/",
                                             linkKind: .relatedTo, linkDirection: .fromInput))
            }
            if let ip = res.page?.ip, entity.kind != .ipAddress, seen.insert("ip:" + ip).inserted {
                result.entities.append(.init(kind: .ipAddress, label: ip, subtitle: "Served from (urlscan.io)",
                                             confidence: 0.6, linkKind: .resolvesTo, linkDirection: .fromInput))
            }
            if let dom = res.page?.domain, entity.kind == .ipAddress,
               !InfraFilter.isInfrastructure(dom), seen.insert("dom:" + dom).inserted {
                result.entities.append(.init(kind: .domain, label: dom.lowercased(), subtitle: "Seen on this IP (urlscan.io)",
                                             confidence: 0.55, linkKind: .hostedOn, linkDirection: .toInput))
            }
        }
        return result
    }
}
