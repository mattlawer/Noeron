//
//  HistoricalDNSPlugin.swift
//  Noeron
//
//  Historical / passive DNS (SecurityTrails): historical A records and subdomains
//  for a domain. Key required.
//

import Foundation

struct HistoricalDNSPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "passivedns", name: "Historical DNS",
              summary: "Historical A records and subdomains for a domain (SecurityTrails).",
              category: .network, acceptedKinds: [.domain],
              producesKinds: [.ipAddress, .subdomain],
              requiresAPIKey: true,
              credentialFields: [.init(key: "securitytrails.apiKey", label: "SecurityTrails API Key")],
              docURL: "https://docs.securitytrails.com", isLive: true, symbol: "clock.arrow.circlepath")
    }

    private struct History: Decodable {
        let records: [Record]?
        struct Record: Decodable {
            let first_seen: String?; let last_seen: String?
            let values: [Value]?
            struct Value: Decodable { let ip: String? }
        }
    }
    private struct Subs: Decodable { let subdomains: [String]? }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("securitytrails.apiKey") else { throw PluginError.missingCredentials("SecurityTrails API key") }
        let domain = WhoisPlugin.normalize(entity.label)
        let headers = ["APIKEY": key, "Accept": "application/json"]
        var result = PluginResult()

        let (histData, histHTTP) = try await context.get(URL(string: "https://api.securitytrails.com/v1/history/\(domain.pathEncoded)/dns/a")!, headers: headers)
        if histHTTP.statusCode == 401 { throw PluginError.missingCredentials("SecurityTrails key rejected") }
        if histHTTP.statusCode == 200, let history = try? JSONDecoder().decode(History.self, from: histData) {
            for rec in (history.records ?? []).prefix(25) {
                for v in rec.values ?? [] {
                    guard let ip = v.ip else { continue }
                    result.entities.append(.init(kind: .ipAddress, label: ip, subtitle: "Historical A record",
                                                 confidence: 0.7, linkKind: .resolvesTo, linkDirection: .fromInput))
                }
                if let d = ISO8601Date.parse(rec.first_seen), let ip = rec.values?.first?.ip {
                    result.events.append(.init(title: "\(domain) → \(ip) first seen", date: d, category: "DNS history"))
                }
            }
        }

        let (subData, subHTTP) = try await context.get(URL(string: "https://api.securitytrails.com/v1/domain/\(domain.pathEncoded)/subdomains")!, headers: headers)
        if subHTTP.statusCode == 200, let subs = try? JSONDecoder().decode(Subs.self, from: subData) {
            for sub in (subs.subdomains ?? []).prefix(40) {
                result.entities.append(.init(kind: .subdomain, label: "\(sub).\(domain)".lowercased(),
                                             subtitle: "SecurityTrails subdomain", confidence: 0.75,
                                             linkKind: .subdomainOf, linkDirection: .toInput))
            }
        }
        result.rawExcerpt = "SecurityTrails: \(result.entities.count) records"
        return result
    }
}
