//
//  GeocodePlugin.swift
//  Noeron
//
//  Geocoding (OpenStreetMap Nominatim, keyless): resolves a place/address to
//  coordinates and a canonical name.
//

import Foundation

struct GeocodePlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "geocode",
            name: "Geocoding (OSM)",
            summary: "Resolves a place/address to coordinates and a canonical name via OpenStreetMap's Nominatim. Keyless.",
            category: .knowledge,
            acceptedKinds: [.location],
            producesKinds: [.url],
            requiresAPIKey: false,
            docURL: "https://nominatim.org/release-docs/latest/api/Search/",
            isLive: true,
            symbol: "mappin.and.ellipse"
        )
    }

    private struct Place: Decodable {
        let lat: String?; let lon: String?; let display_name: String?; let type: String?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [.init(name: "q", value: entity.label),
                            .init(name: "format", value: "json"),
                            .init(name: "limit", value: "1")]
        guard let url = comps.url else { throw PluginError.unsupportedEntity }
        // Nominatim policy: identify the client. (PluginContext already sets a UA.)
        let places = (try? await context.getJSON([Place].self, from: url, headers: ["Accept-Language": "en"])) ?? []
        guard let p = places.first, let lat = p.lat, let lon = p.lon else {
            return PluginResult(rawExcerpt: "No Nominatim match for \(entity.label)")
        }

        var result = PluginResult(rawExcerpt: "Geocoded \(entity.label) → \(lat),\(lon)")
        result.inputAttributes.append(.init(key: "Coordinates", value: "\(lat), \(lon)", source: "Nominatim"))
        if let name = p.display_name { result.inputAttributes.append(.init(key: "Canonical name", value: name, source: "Nominatim")) }
        if let type = p.type { result.inputAttributes.append(.init(key: "Place type", value: type, source: "Nominatim")) }
        result.entities.append(.init(
            kind: .url, label: "https://www.openstreetmap.org/?mlat=\(lat)&mlon=\(lon)#map=14/\(lat)/\(lon)",
            subtitle: "Map (OpenStreetMap)",
            confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
        ))
        return result
    }
}
