//
//  OpenCorporatesPlugin.swift
//  Noeron
//
//  OpenCorporates: company registration, jurisdiction and incorporation date.
//  Key required. Keyless alternative: Company Registry.
//

import Foundation

struct OpenCorporatesPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "opencorporates", name: "OpenCorporates",
              summary: "Company registration, jurisdiction and incorporation date.",
              category: .corporate, acceptedKinds: [.company],
              producesKinds: [.location, .company],
              requiresAPIKey: true,
              credentialFields: [.init(key: "opencorporates.apiKey", label: "OpenCorporates API Token")],
              docURL: "https://api.opencorporates.com/documentation/API-Reference", isLive: true, symbol: "building.2")
    }

    private struct Resp: Decodable {
        let results: Results?
        struct Results: Decodable { let companies: [Wrapper]? }
        struct Wrapper: Decodable { let company: Company? }
        struct Company: Decodable {
            let name: String?; let company_number: String?; let jurisdiction_code: String?
            let incorporation_date: String?; let registered_address_in_full: String?; let opencorporates_url: String?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("opencorporates.apiKey") else { throw PluginError.missingCredentials("OpenCorporates token") }
        var comps = URLComponents(string: "https://api.opencorporates.com/v0.4/companies/search")!
        comps.queryItems = [.init(name: "q", value: entity.label), .init(name: "api_token", value: key), .init(name: "per_page", value: "5")]
        let (data, http) = try await context.get(comps.url!)
        guard http.statusCode == 200 else { return PluginResult(rawExcerpt: "OpenCorporates HTTP \(http.statusCode)") }
        let resp = try decode(Resp.self, data)
        let companies = (resp.results?.companies ?? []).compactMap { $0.company }
        guard let top = companies.first else { return .empty }

        var result = PluginResult(rawExcerpt: "OpenCorporates: \(companies.count) matches")
        if let num = top.company_number { result.inputAttributes.append(.init(key: "Company number", value: num, source: "OpenCorporates")) }
        if let jur = top.jurisdiction_code { result.inputAttributes.append(.init(key: "Jurisdiction", value: jur.uppercased(), source: "OpenCorporates")) }
        if let urlStr = top.opencorporates_url { result.inputAttributes.append(.init(key: "Profile", value: urlStr, kind: .url, source: "OpenCorporates")) }
        if let addr = top.registered_address_in_full {
            result.entities.append(.init(kind: .location, label: addr, subtitle: "Registered office",
                                         confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        if let d = ISO8601Date.parse(top.incorporation_date) {
            result.events.append(.init(title: "Company incorporated: \(top.name ?? entity.label)", date: d, category: "Corporate"))
        }
        return result
    }
}
