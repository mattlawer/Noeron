//
//  ShodanPlugin.swift
//  Noeron
//
//  Shodan: open ports, banners and exposed services for hosts; subdomains for
//  domains. Requires an API key. Keyless alternative: Shodan InternetDB.
//

import Foundation

struct ShodanPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "shodan", name: "Shodan",
              summary: "Open ports, banners and exposed services for hosts; subdomains for domains.",
              category: .threat, acceptedKinds: [.ipAddress, .domain],
              producesKinds: [.domain, .subdomain, .company, .ipAddress, .location],
              requiresAPIKey: true,
              credentialFields: [.init(key: "shodan.apiKey", label: "Shodan API Key")],
              docURL: "https://developer.shodan.io/api", isLive: true, symbol: "server.rack")
    }

    private struct Host: Decodable {
        let ports: [Int]?; let hostnames: [String]?; let org: String?; let isp: String?
        let asn: String?; let country_name: String?; let city: String?
        let data: [Service]?
        struct Service: Decodable { let port: Int?; let product: String?; let version: String?; let transport: String? }
    }
    private struct DomainInfo: Decodable {
        let subdomains: [String]?
        let data: [Record]?
        struct Record: Decodable { let subdomain: String?; let type: String?; let value: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("shodan.apiKey") else { throw PluginError.missingCredentials("Shodan API key") }
        var result = PluginResult()

        if entity.kind == .ipAddress {
            let url = URL(string: "https://api.shodan.io/shodan/host/\(entity.label.pathEncoded)?key=\(key)")!
            let (data, http) = try await context.get(url)
            guard http.statusCode == 200 else { return shodanEmpty(http.statusCode) }
            let host = try decode(Host.self, data)
            result.rawExcerpt = String(decoding: data, as: UTF8.self).truncatedExcerpt()
            if let ports = host.ports, !ports.isEmpty {
                result.inputAttributes.append(.init(key: "Open ports", value: ports.map(String.init).joined(separator: ", "), source: "Shodan"))
            }
            if let org = host.org { result.inputAttributes.append(.init(key: "Org", value: org, source: "Shodan")) }
            if let isp = host.isp { result.inputAttributes.append(.init(key: "ISP", value: isp, source: "Shodan")) }
            for svc in (host.data ?? []).prefix(8) {
                if let port = svc.port, let product = svc.product {
                    result.inputAttributes.append(.init(key: "Port \(port)", value: [product, svc.version].compactMap { $0 }.joined(separator: " "), source: "Shodan"))
                }
            }
            for hostname in (host.hostnames ?? []).prefix(12) {
                result.entities.append(.init(kind: .domain, label: hostname.lowercased(), subtitle: "Shodan hostname",
                                             confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
            }
            if let org = host.org {
                result.entities.append(.init(kind: .company, label: org, subtitle: "Host organisation (Shodan)",
                                             confidence: 0.55, linkKind: .relatedTo, linkDirection: .fromInput))
            }
            if let city = host.city, let country = host.country_name {
                result.entities.append(.init(kind: .location, label: "\(city), \(country)", subtitle: "Shodan geo",
                                             confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
            }
        } else {
            let url = URL(string: "https://api.shodan.io/dns/domain/\(entity.label.pathEncoded)?key=\(key)")!
            let (data, http) = try await context.get(url)
            guard http.statusCode == 200 else { return shodanEmpty(http.statusCode) }
            let info = try decode(DomainInfo.self, data)
            result.rawExcerpt = "Shodan: \(info.subdomains?.count ?? 0) subdomains"
            for sub in (info.subdomains ?? []).prefix(40) {
                result.entities.append(.init(kind: .subdomain, label: "\(sub).\(entity.label)".lowercased(),
                                             subtitle: "Shodan subdomain", confidence: 0.8,
                                             linkKind: .subdomainOf, linkDirection: .toInput))
            }
            for rec in (info.data ?? []).prefix(40) where rec.type == "A" {
                if let ip = rec.value {
                    result.entities.append(.init(kind: .ipAddress, label: ip, subtitle: "A record (Shodan)",
                                                 confidence: 0.7, linkKind: .resolvesTo, linkDirection: .fromInput))
                }
            }
        }
        return result
    }

    private func shodanEmpty(_ code: Int) -> PluginResult {
        PluginResult(rawExcerpt: "Shodan returned HTTP \(code)")
    }
}
