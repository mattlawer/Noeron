//
//  DNSPlugin.swift
//  Noeron
//
//  Live DNS resolution via DNS-over-HTTPS (Cloudflare JSON API). No API key.
//  domain → A/AAAA IPs · MX mail hosts · NS name servers · CNAME · SPF includes.
//

import Foundation

struct DNSPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "dns",
            name: "DNS",
            summary: "Resolves A, AAAA, MX, NS, CNAME and TXT records over DNS-over-HTTPS.",
            category: .network,
            acceptedKinds: [.domain, .subdomain],
            producesKinds: [.ipAddress, .domain, .subdomain],
            isLive: true,
            symbol: "antenna.radiowaves.left.and.right"
        )
    }

    private struct DoHResponse: Decodable {
        let Status: Int
        let Answer: [Answer]?
        struct Answer: Decodable {
            let name: String
            let type: Int
            let TTL: Int?
            let data: String
        }
    }

    private func query(_ name: String, type: String, context: PluginContext) async throws -> [DoHResponse.Answer] {
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        comps.queryItems = [.init(name: "name", value: name), .init(name: "type", value: type)]
        let response = try await context.getJSON(DoHResponse.self, from: comps.url!,
                                                 headers: ["Accept": "application/dns-json"])
        return response.Answer ?? []
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)
        var result = PluginResult()
        var rawLines: [String] = []

        // A / AAAA → IP addresses
        for type in ["A", "AAAA"] {
            for answer in try await query(domain, type: type, context: context) where answer.type == 1 || answer.type == 28 {
                rawLines.append("\(type) \(answer.data)")
                result.entities.append(.init(
                    kind: .ipAddress, label: answer.data,
                    subtitle: type == "AAAA" ? "IPv6 (\(domain))" : "IPv4 (\(domain))",
                    confidence: 0.95,
                    attributes: [.init(key: "Record", value: type, source: "DNS"),
                                 .init(key: "TTL", value: String(answer.TTL ?? 0), kind: .number, source: "DNS")],
                    linkKind: .resolvesTo, linkDirection: .fromInput
                ))
            }
        }

        // MX → mail host domains. Keep as a node only when it's the subject's own
        // mail infrastructure; drop shared providers (Google/Microsoft/etc.) — they
        // are recorded in the raw log but would otherwise explode the graph.
        var mxHosts: [String] = []
        for answer in (try? await query(domain, type: "MX", context: context)) ?? [] where answer.type == 15 {
            let host = (answer.data.split(separator: " ").last.map { String($0) }?.trimmingTrailingDot() ?? answer.data).lowercased()
            rawLines.append("MX \(answer.data)")
            mxHosts.append(host)
            guard !InfraFilter.isInfrastructure(host) else { continue }
            result.entities.append(.init(
                kind: .domain, label: host, subtitle: "Mail server (MX)",
                confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if !mxHosts.isEmpty {
            result.inputAttributes.append(.init(key: "MX", value: mxHosts.prefix(3).joined(separator: ", "), source: "DNS"))
        }

        // NS → name server domains (skip managed-DNS providers like awsdns/cloudflare).
        for answer in (try? await query(domain, type: "NS", context: context)) ?? [] where answer.type == 2 {
            let host = answer.data.trimmingTrailingDot().lowercased()
            rawLines.append("NS \(answer.data)")
            guard !InfraFilter.isInfrastructure(host) else { continue }
            result.entities.append(.init(
                kind: .domain, label: host, subtitle: "Name server (NS)",
                confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // CNAME (skip CDN/hosting targets).
        for answer in (try? await query(domain, type: "CNAME", context: context)) ?? [] where answer.type == 5 {
            let target = answer.data.trimmingTrailingDot().lowercased()
            rawLines.append("CNAME \(answer.data)")
            guard !InfraFilter.isInfrastructure(target) else { continue }
            result.entities.append(.init(
                kind: .domain, label: target, subtitle: "CNAME target",
                confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // TXT → keep SPF as an attribute. SPF includes are always provider
        // infrastructure (e.g. _spf.google.com, sendgrid.net) so they are NOT
        // emitted as nodes — that was pure noise.
        for answer in (try? await query(domain, type: "TXT", context: context)) ?? [] where answer.type == 16 {
            let txt = answer.data.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            rawLines.append("TXT \(txt)")
            if txt.lowercased().hasPrefix("v=spf1") {
                result.inputAttributes.append(.init(key: "SPF", value: txt, source: "DNS"))
            }
        }

        result.rawExcerpt = rawLines.joined(separator: "\n").truncatedExcerpt()
        return result
    }
}

extension String {
    func trimmingTrailingDot() -> String {
        hasSuffix(".") ? String(dropLast()) : self
    }
}
