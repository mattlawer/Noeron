//
//  SubdomainEnumPlugin.swift
//  Noeron
//
//  Passive subdomain discovery from multiple keyless sources (HackerTarget,
//  AlienVault OTX, Certspotter, RapidDNS) — the heart of Amass / Subfinder /
//  theHarvester. Complements crt.sh.
//

import Foundation

/// Extract hostnames that sit under `domain` from arbitrary text/HTML/JSON.
private func hostnames(in text: String, under domain: String) -> [String] {
    let escaped = NSRegularExpression.escapedPattern(for: domain)
    guard let re = try? NSRegularExpression(pattern: "([a-zA-Z0-9_*-]+\\.)+\(escaped)", options: [.caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var out: [String] = []
    for m in re.matches(in: text, range: range) {
        guard let r = Range(m.range, in: text) else { continue }
        let host = String(text[r]).lowercased()
        if !host.contains("*"), host != domain { out.append(host) }
    }
    return out
}

struct SubdomainEnumPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "subdomains",
            name: "Subdomain Enumeration",
            summary: "Passive subdomain discovery from multiple keyless sources (HackerTarget, AlienVault OTX, Certspotter, RapidDNS) — the heart of Amass / Subfinder / theHarvester. Complements crt.sh.",
            category: .network,
            acceptedKinds: [.domain],
            producesKinds: [.subdomain],
            requiresAPIKey: false,
            docURL: "https://github.com/owasp-amass/amass",
            isLive: true,
            symbol: "globe.badge.chevron.backward"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)
        guard domain.contains(".") else { throw PluginError.unsupportedEntity }

        async let ht = hackerTarget(domain, context)
        async let otx = alienVault(domain, context)
        async let cs = certspotter(domain, context)
        async let rd = rapidDNS(domain, context)
        let merged = await (ht + otx + cs + rd)

        var seen = Set<String>()
        var result = PluginResult()
        for host in merged where host.hasSuffix(domain) && host != domain {
            guard seen.insert(host).inserted, seen.count <= 120 else { continue }
            result.entities.append(.init(
                kind: .subdomain, label: host, subtitle: "Passive DNS",
                confidence: 0.8, linkKind: .subdomainOf, linkDirection: .toInput
            ))
        }
        result.inputAttributes.append(.init(key: "Subdomains found", value: String(seen.count), kind: .number, source: "Subdomain Enumeration"))
        result.rawExcerpt = "Passive subdomain enum: \(seen.count) unique hosts for \(domain)"
        return result
    }

    private func hackerTarget(_ domain: String, _ ctx: PluginContext) async -> [String] {
        guard let url = URL(string: "https://api.hackertarget.com/hostsearch/?q=\(domain)"),
              let text = try? await ctx.getString(from: url), !text.contains("API count exceeded"), !text.lowercased().hasPrefix("error") else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { $0.split(separator: ",").first.map { String($0).lowercased() } }
    }

    private struct OTX: Decodable { let passive_dns: [Rec]?; struct Rec: Decodable { let hostname: String? } }
    private func alienVault(_ domain: String, _ ctx: PluginContext) async -> [String] {
        guard let url = URL(string: "https://otx.alienvault.com/api/v1/indicators/domain/\(domain)/passive_dns"),
              let resp = try? await ctx.getJSON(OTX.self, from: url) else { return [] }
        return (resp.passive_dns ?? []).compactMap { $0.hostname?.lowercased() }
    }

    private struct CertspotterIssuance: Decodable { let dns_names: [String]? }
    private func certspotter(_ domain: String, _ ctx: PluginContext) async -> [String] {
        var comps = URLComponents(string: "https://api.certspotter.com/v1/issuances")!
        comps.queryItems = [.init(name: "domain", value: domain),
                            .init(name: "include_subdomains", value: "true"),
                            .init(name: "expand", value: "dns_names")]
        guard let url = comps.url,
              let issuances = try? await ctx.getJSON([CertspotterIssuance].self, from: url) else { return [] }
        return issuances.flatMap { $0.dns_names ?? [] }.map { $0.lowercased() }
    }

    private func rapidDNS(_ domain: String, _ ctx: PluginContext) async -> [String] {
        guard let url = URL(string: "https://rapiddns.io/subdomain/\(domain)?full=1"),
              let html = try? await ctx.getString(from: url) else { return [] }
        return hostnames(in: html, under: domain)
    }
}
