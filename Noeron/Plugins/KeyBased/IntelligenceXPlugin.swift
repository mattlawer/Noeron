//
//  IntelligenceXPlugin.swift
//  Noeron
//
//  Intelligence X: leaks, pastes and dark-web references for a selector. Key required.
//

import Foundation

struct IntelligenceXPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "intelx", name: "Intelligence X",
              summary: "Leaks, pastes and dark-web references for a selector.",
              category: .breach, acceptedKinds: [.email, .domain, .phone, .cryptoWallet, .username],
              producesKinds: [.document],
              requiresAPIKey: true,
              credentialFields: [.init(key: "intelx.apiKey", label: "Intelligence X API Key"),
                                 .init(key: "intelx.host", label: "API host", hint: "default 2.intelx.io", optional: true)],
              docURL: "https://intelx.io/integrations", isLive: true, symbol: "magnifyingglass.circle")
    }

    private struct SearchStart: Decodable { let id: String? }
    private struct SearchResult: Decodable {
        let records: [Record]?
        struct Record: Decodable { let name: String?; let systemid: String?; let bucket: String?; let date: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("intelx.apiKey") else { throw PluginError.missingCredentials("Intelligence X API key") }
        let host = context.credential("intelx.host") ?? "2.intelx.io"
        let base = "https://\(host)"

        // 1. Start a search.
        var startReq = URLRequest(url: URL(string: "\(base)/intelligent/search")!)
        startReq.httpMethod = "POST"
        startReq.setValue(key, forHTTPHeaderField: "x-key")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["term": entity.label, "maxresults": 20, "media": 0, "sort": 2, "terminate": []]
        startReq.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (startData, startResp) = try await context.session.data(for: startReq)
        guard (startResp as? HTTPURLResponse)?.statusCode == 200,
              let start = try? JSONDecoder().decode(SearchStart.self, from: startData),
              let searchID = start.id else {
            throw PluginError.network("Intelligence X search did not start")
        }

        // 2. Give the backend a moment, then fetch results.
        try? await Task.sleep(for: .seconds(2))
        let resultURL = URL(string: "\(base)/intelligent/search/result?id=\(searchID)&limit=20")!
        let (data, _) = try await context.get(resultURL, headers: ["x-key": key])
        let parsed = try decode(SearchResult.self, data)

        var result = PluginResult(rawExcerpt: "IntelX: \(parsed.records?.count ?? 0) records")
        for rec in (parsed.records ?? []).prefix(25) {
            let name = rec.name?.isEmpty == false ? rec.name! : (rec.systemid ?? "record")
            result.entities.append(.init(kind: .document, label: name, subtitle: rec.bucket ?? "Intelligence X",
                                         confidence: 0.6,
                                         sourceURL: rec.systemid.map { "https://intelx.io/?did=\($0)" } ?? "",
                                         linkKind: .mentions, linkDirection: .toInput))
        }
        return result
    }
}
