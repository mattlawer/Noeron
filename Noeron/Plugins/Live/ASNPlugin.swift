//
//  ASNPlugin.swift
//  Noeron
//
//  Live ASN enrichment via BGPView (free, no key).
//  ASN → holder org · website domain · abuse/registration emails · allocation date.
//

import Foundation

struct ASNPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "asn",
            name: "ASN",
            summary: "Autonomous System holder, website, contacts and RIR allocation (BGPView).",
            category: .network,
            acceptedKinds: [.asn],
            producesKinds: [.company, .domain, .email],
            isLive: true,
            symbol: "point.3.connected.trianglepath.dotted"
        )
    }

    private struct ASNResponse: Decodable {
        let status: String?
        let data: ASNData?
        struct ASNData: Decodable {
            let asn: Int?
            let name: String?
            let description_short: String?
            let country_code: String?
            let website: String?
            let email_contacts: [String]?
            let abuse_contacts: [String]?
            let rir_allocation: RIR?
            struct RIR: Decodable {
                let rir_name: String?
                let date_allocated: String?
            }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let number = entity.label.uppercased().replacingOccurrences(of: "AS", with: "")
        guard let asn = Int(number.trimmingCharacters(in: .whitespaces)) else { throw PluginError.unsupportedEntity }
        guard let url = URL(string: "https://api.bgpview.io/asn/\(asn)") else { throw PluginError.unsupportedEntity }

        let response = try await context.getJSON(ASNResponse.self, from: url)
        guard let data = response.data else { return .empty }
        var result = PluginResult(rawExcerpt: "AS\(asn) \(data.description_short ?? data.name ?? "")")

        if let country = data.country_code {
            result.inputAttributes.append(.init(key: "Country", value: country, source: "BGPView"))
        }
        if let name = data.name {
            result.inputAttributes.append(.init(key: "Handle", value: name, source: "BGPView"))
        }

        // Holder org → company
        if let org = data.description_short ?? data.name {
            result.entities.append(.init(
                kind: .company, label: org, subtitle: "AS holder",
                confidence: 0.7, linkKind: .ownedBy, linkDirection: .fromInput
            ))
        }

        // Website → domain
        if let website = data.website, let host = URL(string: website)?.host {
            result.entities.append(.init(
                kind: .domain, label: host.lowercased(), subtitle: "AS website",
                confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // Contacts → emails
        for email in (data.abuse_contacts ?? []) + (data.email_contacts ?? []) {
            result.entities.append(.init(
                kind: .email, label: email.lowercased(), subtitle: "AS contact",
                confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // Allocation date → timeline
        if let raw = data.rir_allocation?.date_allocated {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = f.date(from: raw) {
                result.events.append(.init(title: "AS\(asn) allocated", date: date, precision: .day,
                                           category: "ASN", detail: data.rir_allocation?.rir_name ?? ""))
            }
        }

        return result
    }
}
