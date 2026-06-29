//
//  XposedOrNotPlugin.swift
//  Noeron
//
//  XposedOrNot (free, keyless): the breaches an email appears in, with dates and
//  exposed data types. A no-key alternative to HaveIBeenPwned. (Mozilla Monitor is
//  built on HIBP and still needs that paid key, so XposedOrNot is the keyless one.)
//

import Foundation

struct XposedOrNotPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "xposedornot",
            name: "XposedOrNot",
            summary: "Free, keyless breach lookup for an email — the breaches it appears in, with dates and exposed data types. A no-key alternative to HaveIBeenPwned.",
            category: .breach,
            acceptedKinds: [.email],
            producesKinds: [.breach],
            requiresAPIKey: false,
            docURL: "https://xposedornot.com/api_doc",
            isLive: true,
            symbol: "shield.lefthalf.filled"
        )
    }

    private struct Analytics: Decodable {
        let ExposedBreaches: Exposed?
        struct Exposed: Decodable { let breaches_details: [Detail]? }
        struct Detail: Decodable {
            let breach: String?; let domain: String?; let industry: String?
            let xposed_data: String?; let xposed_date: String?
            let xposed_records: Int?; let password_risk: String?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard EmailIntel.parts(of: entity.label) != nil else { throw PluginError.unsupportedEntity }
        var comps = URLComponents(string: "https://api.xposedornot.com/v1/breach-analytics")!
        comps.queryItems = [.init(name: "email", value: entity.label)]
        guard let url = comps.url else { throw PluginError.unsupportedEntity }

        let (data, http) = try await context.get(url)
        guard http.statusCode == 200,
              let analytics = try? JSONDecoder().decode(Analytics.self, from: data),
              let breaches = analytics.ExposedBreaches?.breaches_details, !breaches.isEmpty else {
            return PluginResult(rawExcerpt: http.statusCode == 404 ? "No breaches found" : "XposedOrNot: no breach data")
        }

        var result = PluginResult(rawExcerpt: "XposedOrNot: \(breaches.count) breaches for \(entity.label)")
        for b in breaches {
            let name = b.breach ?? b.domain ?? "Breach"
            var attrs: [EntityAttribute] = []
            if let records = b.xposed_records { attrs.append(.init(key: "Accounts", value: records.formatted(), kind: .number, source: "XposedOrNot")) }
            if let exposed = b.xposed_data, !exposed.isEmpty { attrs.append(.init(key: "Exposed", value: exposed.replacingOccurrences(of: ";", with: ", "), source: "XposedOrNot")) }
            if let risk = b.password_risk, !risk.isEmpty { attrs.append(.init(key: "Password risk", value: risk, source: "XposedOrNot")) }
            if let date = b.xposed_date, !date.isEmpty { attrs.append(.init(key: "Breach date", value: date, kind: .date, source: "XposedOrNot")) }
            result.entities.append(.init(kind: .breach, label: name, subtitle: b.domain ?? "",
                                         confidence: 0.85, attributes: attrs,
                                         linkKind: .appearsIn, linkDirection: .fromInput))
            if let d = ISO8601Date.parse(b.xposed_date) {
                result.events.append(.init(title: "Email in breach: \(name)", date: d, precision: .year, category: "Breach", detail: entity.label))
            }
        }
        return result
    }
}
