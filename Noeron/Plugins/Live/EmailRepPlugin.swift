//
//  EmailRepPlugin.swift
//  Noeron
//
//  EmailRep (keyless free tier): reputation, deliverability, breach/credential-leak
//  flags and known online profiles for an email.
//

import Foundation

struct EmailRepPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "emailrep",
            name: "EmailRep",
            summary: "Reputation, deliverability, breach/credential-leak flags and known online profiles for an email. Uses the keyless free tier (rate-limited).",
            category: .breach,
            acceptedKinds: [.email],
            producesKinds: [.socialProfile, .breach],
            requiresAPIKey: false,
            docURL: "https://emailrep.io/docs/",
            isLive: true,
            symbol: "gauge.with.dots.needle.bottom.50percent"
        )
    }

    private struct Report: Decodable {
        let reputation: String?
        let suspicious: Bool?
        let references: Int?
        let details: Details?
        struct Details: Decodable {
            let blacklisted: Bool?
            let malicious_activity: Bool?
            let credentials_leaked: Bool?
            let data_breach: Bool?
            let first_seen: String?
            let last_seen: String?
            let domain_exists: Bool?
            let domain_reputation: String?
            let free_provider: Bool?
            let disposable: Bool?
            let deliverable: Bool?
            let spoofable: Bool?
            let spf_strict: Bool?
            let dmarc_enforced: Bool?
            let profiles: [String]?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard EmailIntel.parts(of: entity.label) != nil,
              let url = URL(string: "https://emailrep.io/\(entity.label.pathEncoded)") else { throw PluginError.unsupportedEntity }

        // `context.get` maps HTTP 429 to `PluginError.rateLimited`, which would
        // surface as a failure. EmailRep's keyless tier rate-limits aggressively,
        // so treat that (and 401) as a soft "no data" result rather than an error.
        let data: Data, http: HTTPURLResponse
        do {
            (data, http) = try await context.get(url, headers: ["Accept": "application/json"])
        } catch PluginError.rateLimited {
            return PluginResult(rawExcerpt: "EmailRep keyless tier rate-limited — try again later.")
        }
        guard http.statusCode == 200, let report = try? JSONDecoder().decode(Report.self, from: data) else {
            if http.statusCode == 401 || http.statusCode == 429 {
                return PluginResult(rawExcerpt: "EmailRep keyless tier rate-limited — try again later.")
            }
            return PluginResult(rawExcerpt: "EmailRep HTTP \(http.statusCode)")
        }

        var result = PluginResult(rawExcerpt: String(decoding: data, as: UTF8.self).truncatedExcerpt())
        if let rep = report.reputation { result.inputAttributes.append(.init(key: "Reputation", value: rep, source: "EmailRep")) }
        if let refs = report.references { result.inputAttributes.append(.init(key: "References", value: String(refs), kind: .number, source: "EmailRep")) }
        if let d = report.details {
            if let deliverable = d.deliverable { result.inputAttributes.append(.init(key: "Deliverable", value: deliverable ? "Yes" : "No", kind: .boolean, source: "EmailRep")) }
            if d.spoofable == true { result.inputAttributes.append(.init(key: "Spoofable", value: "Yes (weak SPF/DMARC)", kind: .boolean, source: "EmailRep")) }
            if let first = d.first_seen, first != "never", let date = ISO8601Date.parse(first) {
                result.events.append(.init(title: "Email first seen online", date: date, category: "Exposure", detail: "EmailRep"))
            }
            if let last = d.last_seen, last != "never", let date = ISO8601Date.parse(last) {
                result.events.append(.init(title: "Email last seen online", date: date, category: "Exposure", detail: "EmailRep"))
            }
            if d.credentials_leaked == true || d.data_breach == true {
                let what = d.credentials_leaked == true ? "Credentials leaked" : "Seen in a data breach"
                result.entities.append(.init(
                    kind: .breach, label: what, subtitle: "Flagged by EmailRep",
                    confidence: 0.7, linkKind: .appearsIn, linkDirection: .fromInput
                ))
            }
            for profile in d.profiles ?? [] {
                result.entities.append(.init(
                    kind: .socialProfile, label: profile, subtitle: "Profile linked to email (EmailRep)",
                    confidence: 0.55, linkKind: .hasProfile, linkDirection: .toInput
                ))
            }
        }
        return result
    }
}
