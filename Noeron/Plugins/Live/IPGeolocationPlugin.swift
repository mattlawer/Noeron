//
//  IPGeolocationPlugin.swift
//  Noeron
//
//  Live IP geolocation via ipwho.is (free, HTTPS, no key).
//  ip → location · ASN · owning org / ISP · reverse domain.
//

import Foundation

struct IPGeolocationPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "ipgeo",
            name: "IP Geolocation",
            summary: "City/country, owning organisation, ISP and ASN for an IP address.",
            category: .network,
            acceptedKinds: [.ipAddress],
            producesKinds: [.location, .asn, .company, .domain],
            isLive: true,
            symbol: "mappin.and.ellipse"
        )
    }

    private struct GeoResponse: Decodable {
        let success: Bool?
        let ip: String?
        let type: String?
        let country: String?
        let country_code: String?
        let region: String?
        let city: String?
        let latitude: Double?
        let longitude: Double?
        let postal: String?
        let connection: Connection?
        struct Connection: Decodable {
            let asn: Int?
            let org: String?
            let isp: String?
            let domain: String?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let ip = entity.label.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://ipwho.is/\(ip)") else { throw PluginError.unsupportedEntity }
        let geo = try await context.getJSON(GeoResponse.self, from: url)
        guard geo.success != false else { return .empty }

        var result = PluginResult()
        var raw: [String] = []

        // Input attributes
        if let c = geo.country { result.inputAttributes.append(.init(key: "Country", value: c, source: "ipwho.is")); raw.append("country=\(c)") }
        if let city = geo.city { result.inputAttributes.append(.init(key: "City", value: city, source: "ipwho.is")) }
        if let isp = geo.connection?.isp { result.inputAttributes.append(.init(key: "ISP", value: isp, source: "ipwho.is")) }

        // Location node
        if let city = geo.city, let country = geo.country {
            let label = [city, geo.region, country].compactMap { $0 }.joined(separator: ", ")
            var attrs: [EntityAttribute] = []
            if let lat = geo.latitude, let lon = geo.longitude {
                attrs.append(.init(key: "Coordinates", value: String(format: "%.4f, %.4f", lat, lon), source: "ipwho.is"))
            }
            if let postal = geo.postal { attrs.append(.init(key: "Postal", value: postal, source: "ipwho.is")) }
            result.entities.append(.init(
                kind: .location, label: label, subtitle: "Approx. IP location",
                confidence: 0.7, attributes: attrs, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // ASN node
        if let asn = geo.connection?.asn, asn > 0 {
            result.entities.append(.init(
                kind: .asn, label: "AS\(asn)", subtitle: geo.connection?.org ?? "",
                confidence: 0.9,
                attributes: [.init(key: "Organisation", value: geo.connection?.org ?? "", source: "ipwho.is")],
                linkKind: .partOf, linkDirection: .fromInput
            ))
            raw.append("asn=AS\(asn)")
        }

        // Owning org → company
        if let org = geo.connection?.org, !org.isEmpty {
            result.entities.append(.init(
                kind: .company, label: org, subtitle: "IP owner / ISP",
                confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // Reverse / connection domain — record as an attribute, but only make it a
        // node when it isn't generic ISP/cloud infrastructure (those just sprawl).
        if let domain = geo.connection?.domain, domain.contains(".") {
            let host = domain.lowercased()
            result.inputAttributes.append(.init(key: "Network domain", value: host, source: "ipwho.is"))
            if !InfraFilter.isInfrastructure(host) {
                result.entities.append(.init(
                    kind: .domain, label: host, subtitle: "Network domain",
                    confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput
                ))
            }
        }

        result.rawExcerpt = raw.joined(separator: " · ")
        return result
    }
}
