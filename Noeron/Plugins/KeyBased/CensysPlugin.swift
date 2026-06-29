//
//  CensysPlugin.swift
//  Noeron
//
//  Censys (Search API v2, Basic auth): host services, software and AS data from
//  internet scans for an IP. Requires API ID + Secret.
//

import Foundation

struct CensysPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "censys", name: "Censys",
              summary: "Host services, software and autonomous-system data from internet scans.",
              category: .threat, acceptedKinds: [.ipAddress],
              producesKinds: [.company, .location, .asn],
              requiresAPIKey: true,
              credentialFields: [.init(key: "censys.apiID", label: "API ID"),
                                 .init(key: "censys.apiSecret", label: "API Secret")],
              docURL: "https://search.censys.io/api", isLive: true, symbol: "scope")
    }

    private struct Resp: Decodable {
        let result: HostResult?
        struct HostResult: Decodable {
            let services: [Service]?
            let autonomous_system: AS?
            let location: Loc?
            struct Service: Decodable { let port: Int?; let service_name: String? }
            struct AS: Decodable { let asn: Int?; let name: String? }
            struct Loc: Decodable { let country: String?; let city: String? }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let id = context.credential("censys.apiID"), let secret = context.credential("censys.apiSecret") else {
            throw PluginError.missingCredentials("Censys API ID + Secret")
        }
        let url = URL(string: "https://search.censys.io/api/v2/hosts/\(entity.label.pathEncoded)")!
        let (data, http) = try await context.get(url, headers: ["Authorization": id.basicAuthHeader(password: secret),
                                                                 "Accept": "application/json"])
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw PluginError.missingCredentials("Censys credentials rejected") }
            return PluginResult(rawExcerpt: "Censys HTTP \(http.statusCode)")
        }
        let resp = try decode(Resp.self, data)
        guard let r = resp.result else { return .empty }
        var result = PluginResult(rawExcerpt: String(decoding: data, as: UTF8.self).truncatedExcerpt())

        let ports = (r.services ?? []).compactMap { $0.port }.map(String.init)
        if !ports.isEmpty { result.inputAttributes.append(.init(key: "Open ports", value: ports.joined(separator: ", "), source: "Censys")) }
        if let asn = r.autonomous_system?.asn {
            result.entities.append(.init(kind: .asn, label: "AS\(asn)", subtitle: r.autonomous_system?.name ?? "",
                                         confidence: 0.8, linkKind: .partOf, linkDirection: .fromInput))
        }
        if let name = r.autonomous_system?.name {
            result.entities.append(.init(kind: .company, label: name, subtitle: "AS holder (Censys)",
                                         confidence: 0.55, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        if let country = r.location?.country {
            let label = [r.location?.city, country].compactMap { $0 }.joined(separator: ", ")
            result.entities.append(.init(kind: .location, label: label, subtitle: "Censys geo",
                                         confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        return result
    }
}
