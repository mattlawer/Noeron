//
//  LinkedInPlugin.swift
//  Noeron
//
//  LinkedIn enrichment (Proxycurl reverse work-email lookup): resolve a work email
//  to a LinkedIn profile — name, role, employer. Key required.
//

import Foundation

struct LinkedInPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "linkedin", name: "LinkedIn Enrichment",
              summary: "Resolve a work email to a LinkedIn profile: name, role, employer (via Proxycurl).",
              category: .social, acceptedKinds: [.email],
              producesKinds: [.person, .company, .url],
              requiresAPIKey: true,
              credentialFields: [.init(key: "linkedin.apiKey", label: "Proxycurl API Key")],
              docURL: "https://nubela.co/proxycurl/docs", isLive: true, symbol: "person.text.rectangle")
    }

    private struct Resp: Decodable {
        let profile: Profile?
        let url: String?
        struct Profile: Decodable {
            let full_name: String?; let occupation: String?; let city: String?
            let experiences: [Exp]?
            struct Exp: Decodable { let company: String?; let title: String? }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("linkedin.apiKey") else { throw PluginError.missingCredentials("Proxycurl API key") }
        var comps = URLComponents(string: "https://nubela.co/proxycurl/api/linkedin/profile/resolve/email")!
        comps.queryItems = [.init(name: "email", value: entity.label),
                            .init(name: "enrich_profile", value: "enrich")]
        let (data, http) = try await context.get(comps.url!, headers: ["Authorization": "Bearer \(key)"])
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 { throw PluginError.missingCredentials("Proxycurl key rejected") }
            return PluginResult(rawExcerpt: "Proxycurl HTTP \(http.statusCode)")
        }
        let resp = try decode(Resp.self, data)
        var result = PluginResult(rawExcerpt: String(decoding: data, as: UTF8.self).truncatedExcerpt())

        if let urlStr = resp.url {
            result.entities.append(.init(kind: .url, label: urlStr, subtitle: "LinkedIn profile",
                                         confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        if let p = resp.profile {
            if let name = p.full_name {
                result.entities.append(.init(kind: .person, label: name, subtitle: p.occupation ?? "LinkedIn",
                                             confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
            }
            if let employer = p.experiences?.first?.company {
                result.entities.append(.init(kind: .company, label: employer, subtitle: "Current employer (LinkedIn)",
                                             confidence: 0.6, linkKind: .memberOf, linkDirection: .fromInput))
            }
            if let occ = p.occupation { result.inputAttributes.append(.init(key: "Headline", value: occ, source: "LinkedIn")) }
        }
        return result
    }
}
