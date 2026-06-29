//
//  SSLCertificatePlugin.swift
//  Noeron
//
//  Live certificate discovery via Certificate Transparency logs (crt.sh). No key.
//  domain → issued certificates (issuer, serial, validity) + subdomains harvested
//  from Subject Alternative Names. CT logs are the canonical OSINT subdomain source.
//

import Foundation

struct SSLCertificatePlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "ssl.ct",
            name: "SSL Certificates",
            summary: "Certificate Transparency lookup (crt.sh): issued certs + SAN subdomains.",
            category: .network,
            acceptedKinds: [.domain],
            producesKinds: [.certificate, .subdomain],
            isLive: true,
            symbol: "checkmark.seal.fill"
        )
    }

    private struct CrtEntry: Decodable {
        let issuer_name: String?
        let common_name: String?
        let name_value: String?
        let not_before: String?
        let not_after: String?
        let serial_number: String?
        let id: Int?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)
        var comps = URLComponents(string: "https://crt.sh/")!
        comps.queryItems = [.init(name: "q", value: domain), .init(name: "output", value: "json")]

        let (data, _) = try await context.get(comps.url!, timeout: 25)
        let entries = (try? JSONDecoder().decode([CrtEntry].self, from: data)) ?? []
        guard !entries.isEmpty else { return .empty }

        var result = PluginResult(rawExcerpt: "\(entries.count) CT log entries for \(domain)")
        var seenSubdomains = Set<String>()
        var seenSerials = Set<String>()

        // Most recent first (crt.sh returns newest-ish; sort by not_before desc).
        let sorted = entries.sorted { ($0.not_before ?? "") > ($1.not_before ?? "") }

        for entry in sorted {
            // Harvest SAN subdomains.
            let names = (entry.name_value ?? "").split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            for name in names where name.hasSuffix(domain) && name != domain && !name.contains("*") {
                if seenSubdomains.insert(name).inserted, seenSubdomains.count <= 50 {
                    result.entities.append(.init(
                        kind: .subdomain, label: name, subtitle: "From CT log SAN",
                        confidence: 0.85, linkKind: .subdomainOf, linkDirection: .toInput
                    ))
                }
            }

            // Keep the few most recent distinct certificates as nodes.
            let serial = entry.serial_number ?? String(entry.id ?? 0)
            if seenSerials.insert(serial).inserted, seenSerials.count <= 6 {
                let cn = entry.common_name ?? names.first ?? domain
                var attrs: [EntityAttribute] = [
                    .init(key: "Issuer", value: SSLCertificatePlugin.shortIssuer(entry.issuer_name), source: "crt.sh"),
                    .init(key: "Serial", value: serial, source: "crt.sh")
                ]
                if let nb = entry.not_before { attrs.append(.init(key: "Valid from", value: nb, kind: .date, source: "crt.sh")) }
                if let na = entry.not_after { attrs.append(.init(key: "Valid to", value: na, kind: .date, source: "crt.sh")) }

                result.entities.append(.init(
                    kind: .certificate, label: cn,
                    subtitle: SSLCertificatePlugin.shortIssuer(entry.issuer_name),
                    confidence: 0.9, attributes: attrs,
                    sourceURL: entry.id.map { "https://crt.sh/?id=\($0)" } ?? "",
                    linkKind: .issuedFor, linkDirection: .toInput
                ))

                if let issued = SSLCertificatePlugin.date(entry.not_before) {
                    result.events.append(.init(title: "Certificate issued for \(cn)", date: issued,
                                               category: "Certificate", detail: SSLCertificatePlugin.shortIssuer(entry.issuer_name)))
                }
                if let expires = SSLCertificatePlugin.date(entry.not_after) {
                    result.events.append(.init(title: "Certificate expires for \(cn)", date: expires,
                                               category: "Certificate"))
                }
            }
        }
        return result
    }

    static func shortIssuer(_ raw: String?) -> String {
        guard let raw else { return "Unknown CA" }
        // issuer_name like "C=US, O=Let's Encrypt, CN=R3"
        if let o = raw.split(separator: ",").first(where: { $0.contains("O=") }) {
            return o.replacingOccurrences(of: "O=", with: "").trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(raw.prefix(19)))
    }
}
