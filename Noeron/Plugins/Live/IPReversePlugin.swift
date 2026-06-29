//
//  IPReversePlugin.swift
//  Noeron
//
//  Reverse IP & PTR (keyless): PTR (reverse DNS) plus other domains co-hosted on
//  the same IP (HackerTarget reverse-IP). Complements IP Geolocation & ASN.
//

import Foundation

struct IPReversePlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "ip-reverse",
            name: "Reverse IP / PTR",
            summary: "PTR (reverse DNS) and other domains co-hosted on the same IP (HackerTarget reverse-IP). Keyless. Complements IP Geolocation & ASN.",
            category: .network,
            acceptedKinds: [.ipAddress],
            producesKinds: [.domain],
            requiresAPIKey: false,
            docURL: "https://hackertarget.com/reverse-ip-lookup/",
            isLive: true,
            symbol: "arrow.uturn.backward.circle"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let ip = entity.label.trimmingCharacters(in: .whitespaces)
        var result = PluginResult()
        var seen = Set<String>()

        // PTR via DoH (IPv4 in-addr.arpa).
        let octets = ip.split(separator: ".").map(String.init)
        if octets.count == 4 {
            let ptrName = "\(octets.reversed().joined(separator: ".")).in-addr.arpa"
            for ptr in await DNSoverHTTPS.query(ptrName, type: "PTR", context: context) {
                let host = ptr.trimmingTrailingDot().lowercased()
                if seen.insert(host).inserted {
                    result.inputAttributes.append(.init(key: "PTR", value: host, source: "Reverse IP / PTR"))
                    guard !InfraFilter.isInfrastructure(host) else { continue }
                    result.entities.append(.init(kind: .domain, label: host, subtitle: "Reverse DNS (PTR)",
                                                 confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
                }
            }
        }

        // Reverse IP: other domains hosted on this address.
        if let url = URL(string: "https://api.hackertarget.com/reverseiplookup/?q=\(ip)"),
           let text = try? await context.getString(from: url),
           !text.contains("API count exceeded"), !text.lowercased().hasPrefix("error"), !text.contains("no records") {
            for line in text.split(whereSeparator: \.isNewline) {
                let host = line.trimmingCharacters(in: .whitespaces).lowercased()
                guard !host.isEmpty, host.contains("."), !InfraFilter.isInfrastructure(host),
                      seen.insert(host).inserted, seen.count <= 60 else { continue }
                result.entities.append(.init(kind: .domain, label: host, subtitle: "Co-hosted on this IP",
                                             confidence: 0.6, linkKind: .hostedOn, linkDirection: .toInput))
            }
        }
        result.inputAttributes.append(.init(key: "Domains on IP", value: String(seen.count), kind: .number, source: "Reverse IP / PTR"))
        result.rawExcerpt = "Reverse IP/PTR: \(seen.count) hostnames for \(ip)"
        return result
    }
}
