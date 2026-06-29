//
//  ShodanInternetDBPlugin.swift
//  Noeron
//
//  Shodan InternetDB (free, keyless): open ports, hostnames and known CVEs for an
//  IP. A no-key alternative to the full Shodan API.
//

import Foundation

struct ShodanInternetDBPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "internetdb",
            name: "Shodan InternetDB",
            summary: "Free, keyless open ports, hostnames and known CVEs for an IP via Shodan's InternetDB. A no-key alternative to the full Shodan API.",
            category: .threat,
            acceptedKinds: [.ipAddress],
            producesKinds: [.domain],
            requiresAPIKey: false,
            docURL: "https://internetdb.shodan.io/",
            isLive: true,
            symbol: "lock.shield"
        )
    }

    private struct Resp: Decodable {
        let ports: [Int]?
        let hostnames: [String]?
        let cpes: [String]?
        let tags: [String]?
        let vulns: [String]?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let ip = entity.label.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://internetdb.shodan.io/\(ip)") else { throw PluginError.unsupportedEntity }
        let (data, http) = try await context.get(url)
        guard http.statusCode == 200, let r = try? JSONDecoder().decode(Resp.self, from: data) else {
            return PluginResult(rawExcerpt: http.statusCode == 404 ? "No InternetDB record" : "InternetDB HTTP \(http.statusCode)")
        }

        var result = PluginResult(rawExcerpt: "InternetDB: \(r.ports?.count ?? 0) ports, \(r.vulns?.count ?? 0) CVEs for \(ip)")
        if let ports = r.ports, !ports.isEmpty {
            result.inputAttributes.append(.init(key: "Open ports", value: ports.sorted().map(String.init).joined(separator: ", "), source: "InternetDB"))
        }
        if let tags = r.tags, !tags.isEmpty {
            result.inputAttributes.append(.init(key: "Tags", value: tags.joined(separator: ", "), source: "InternetDB"))
        }
        if let vulns = r.vulns, !vulns.isEmpty {
            result.inputAttributes.append(.init(key: "Vulnerabilities", value: vulns.prefix(15).joined(separator: ", "), source: "InternetDB"))
        }
        if let cpes = r.cpes, !cpes.isEmpty {
            result.inputAttributes.append(.init(key: "Software (CPE)", value: cpes.prefix(8).joined(separator: ", "), source: "InternetDB"))
        }
        for host in (r.hostnames ?? []) where !InfraFilter.isInfrastructure(host) {
            result.entities.append(.init(kind: .domain, label: host.lowercased(), subtitle: "Hostname on this IP (InternetDB)",
                                         confidence: 0.65, linkKind: .hostedOn, linkDirection: .toInput))
        }
        return result
    }
}
