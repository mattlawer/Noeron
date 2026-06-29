//
//  HunterPlugin.swift
//  Noeron
//
//  Hunter.io: email addresses, names and roles for a domain or company. Key required.
//

import Foundation

struct HunterPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "hunter", name: "Hunter",
              summary: "Email addresses, names and roles for a domain or company.",
              category: .corporate, acceptedKinds: [.domain, .company],
              producesKinds: [.email, .person],
              requiresAPIKey: true,
              credentialFields: [.init(key: "hunter.apiKey", label: "Hunter API Key")],
              docURL: "https://hunter.io/api-documentation", isLive: true, symbol: "envelope.badge")
    }

    private struct Resp: Decodable {
        let data: DataObj?
        struct DataObj: Decodable {
            let pattern: String?
            let emails: [Email]?
            struct Email: Decodable {
                let value: String?; let first_name: String?; let last_name: String?
                let position: String?; let confidence: Int?
            }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("hunter.apiKey") else { throw PluginError.missingCredentials("Hunter API key") }
        var comps = URLComponents(string: "https://api.hunter.io/v2/domain-search")!
        comps.queryItems = [
            entity.kind == .domain ? .init(name: "domain", value: WhoisPlugin.normalize(entity.label))
                                   : .init(name: "company", value: entity.label),
            .init(name: "api_key", value: key),
            .init(name: "limit", value: "25")
        ]
        let (data, http) = try await context.get(comps.url!)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw PluginError.missingCredentials("Hunter key rejected") }
            return PluginResult(rawExcerpt: "Hunter HTTP \(http.statusCode)")
        }
        let resp = try decode(Resp.self, data)
        var result = PluginResult(rawExcerpt: "Hunter: \(resp.data?.emails?.count ?? 0) emails")
        if let pattern = resp.data?.pattern { result.inputAttributes.append(.init(key: "Email pattern", value: pattern, source: "Hunter")) }
        for e in (resp.data?.emails ?? []).prefix(40) {
            guard let value = e.value else { continue }
            let name = [e.first_name, e.last_name].compactMap { $0 }.joined(separator: " ")
            result.entities.append(.init(kind: .email, label: value.lowercased(),
                                         subtitle: e.position ?? "Found by Hunter",
                                         confidence: Double(e.confidence ?? 50) / 100.0,
                                         linkKind: .hasEmail, linkDirection: .fromInput))
            if !name.isEmpty {
                result.entities.append(.init(kind: .person, label: name, subtitle: e.position ?? "",
                                             confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
            }
        }
        return result
    }
}
