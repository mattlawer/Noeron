//
//  HaveIBeenPwnedPlugin.swift
//  Noeron
//
//  HaveIBeenPwned: data breaches an email address appears in. Key required.
//  Keyless alternative: XposedOrNot.
//

import Foundation

struct HaveIBeenPwnedPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "hibp", name: "HaveIBeenPwned",
              summary: "Data breaches an email address appears in.",
              category: .breach, acceptedKinds: [.email],
              producesKinds: [.breach],
              requiresAPIKey: true,
              credentialFields: [.init(key: "hibp.apiKey", label: "HIBP API Key")],
              docURL: "https://haveibeenpwned.com/API/v3", isLive: true, symbol: "exclamationmark.shield")
    }

    private struct Breach: Decodable {
        let Name: String?; let Title: String?; let BreachDate: String?
        let PwnCount: Int?; let Domain: String?; let DataClasses: [String]?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("hibp.apiKey") else { throw PluginError.missingCredentials("HIBP API key") }
        let url = URL(string: "https://haveibeenpwned.com/api/v3/breachedaccount/\(entity.label.pathEncoded)?truncateResponse=false")!
        let (data, http) = try await context.get(url, headers: ["hibp-api-key": key])
        if http.statusCode == 404 { return PluginResult(rawExcerpt: "No breaches found") }
        if http.statusCode == 401 { throw PluginError.missingCredentials("HIBP key rejected") }
        guard http.statusCode == 200 else { return PluginResult(rawExcerpt: "HIBP HTTP \(http.statusCode)") }

        let breaches = try decode([Breach].self, data)
        var result = PluginResult(rawExcerpt: "HIBP: \(breaches.count) breaches")
        for b in breaches {
            let title = b.Title ?? b.Name ?? "Breach"
            var attrs: [EntityAttribute] = []
            if let count = b.PwnCount { attrs.append(.init(key: "Accounts", value: count.formatted(), kind: .number, source: "HIBP")) }
            if let classes = b.DataClasses { attrs.append(.init(key: "Exposed", value: classes.prefix(6).joined(separator: ", "), source: "HIBP")) }
            if let date = b.BreachDate { attrs.append(.init(key: "Breach date", value: date, kind: .date, source: "HIBP")) }
            result.entities.append(.init(kind: .breach, label: title, subtitle: b.Domain ?? "",
                                         confidence: 0.9, attributes: attrs,
                                         linkKind: .appearsIn, linkDirection: .fromInput))
            if let d = ISO8601Date.parse(b.BreachDate) {
                result.events.append(.init(title: "Email in breach: \(title)", date: d, category: "Breach", detail: entity.label))
            }
        }
        return result
    }
}
