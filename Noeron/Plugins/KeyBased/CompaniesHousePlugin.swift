//
//  CompaniesHousePlugin.swift
//  Noeron
//
//  Companies House (UK): company profile and active officers. Key required.
//

import Foundation

struct CompaniesHousePlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "companieshouse", name: "Companies House",
              summary: "UK company profile and active officers.",
              category: .corporate, acceptedKinds: [.company],
              producesKinds: [.person, .location],
              requiresAPIKey: true,
              credentialFields: [.init(key: "companieshouse.apiKey", label: "Companies House API Key")],
              docURL: "https://developer.company-information.service.gov.uk", isLive: true, symbol: "building.columns")
    }

    private struct Search: Decodable {
        let items: [Item]?
        struct Item: Decodable { let title: String?; let company_number: String?; let address_snippet: String?; let date_of_creation: String? }
    }
    private struct Officers: Decodable {
        let items: [Officer]?
        struct Officer: Decodable { let name: String?; let officer_role: String?; let appointed_on: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("companieshouse.apiKey") else { throw PluginError.missingCredentials("Companies House API key") }
        let auth = ["Authorization": key.basicAuthHeader()]

        var comps = URLComponents(string: "https://api.company-information.service.gov.uk/search/companies")!
        comps.queryItems = [.init(name: "q", value: entity.label), .init(name: "items_per_page", value: "5")]
        let (data, http) = try await context.get(comps.url!, headers: auth)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw PluginError.missingCredentials("Companies House key rejected") }
            return PluginResult(rawExcerpt: "Companies House HTTP \(http.statusCode)")
        }
        let search = try decode(Search.self, data)
        guard let top = search.items?.first, let number = top.company_number else { return .empty }

        var result = PluginResult(rawExcerpt: "Companies House: \(top.title ?? "")")
        result.inputAttributes.append(.init(key: "Company number", value: number, source: "Companies House"))
        if let addr = top.address_snippet {
            result.entities.append(.init(kind: .location, label: addr, subtitle: "Registered office",
                                         confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        if let d = ISO8601Date.parse(top.date_of_creation) {
            result.events.append(.init(title: "Company incorporated: \(top.title ?? entity.label)", date: d, category: "Corporate"))
        }

        // Officers
        let (offData, offHTTP) = try await context.get(URL(string: "https://api.company-information.service.gov.uk/company/\(number)/officers")!, headers: auth)
        if offHTTP.statusCode == 200, let officers = try? JSONDecoder().decode(Officers.self, from: offData) {
            for o in (officers.items ?? []).prefix(15) {
                guard let name = o.name else { continue }
                result.entities.append(.init(kind: .person, label: name, subtitle: o.officer_role ?? "Officer",
                                             confidence: 0.7, linkKind: .ownedBy, linkDirection: .fromInput))
            }
        }
        return result
    }
}
