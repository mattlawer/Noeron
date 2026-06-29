//
//  EmailIntelPlugin.swift
//  Noeron
//
//  Keyless email parsing & enrichment. The cornerstone of "paste an email, get a
//  graph": it derives the `.domain` and a `.username` candidate from the address
//  (which unlock every other keyless plugin), classifies the provider, and
//  identifies the mail host via MX. Shared helpers live in `EmailIntel`.
//

import Foundation

// Minimal DNS-over-HTTPS MX lookup used only here.
private enum MXLookup {
    struct Response: Decodable {
        let Answer: [Answer]?
        struct Answer: Decodable { let type: Int; let data: String }
    }
    /// Returns MX target hostnames for a domain (empty if none / on any error).
    static func hosts(for domain: String, context: PluginContext) async -> [String] {
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        comps.queryItems = [.init(name: "name", value: domain), .init(name: "type", value: "MX")]
        guard let url = comps.url,
              let resp = try? await context.getJSON(Response.self, from: url, headers: ["Accept": "application/dns-json"])
        else { return [] }
        return (resp.Answer ?? [])
            .filter { $0.type == 15 }
            .map { $0.data.split(separator: " ").last.map(String.init)?.trimmingTrailingDot() ?? $0.data }
            .map { $0.lowercased() }
    }
}

struct EmailIntelPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "email-intel",
            name: "Email Intelligence",
            summary: "Parses an address into its domain and username, classifies the provider (free / corporate / disposable / role), and identifies the mail host via MX. Fans the graph out to the domain and a username candidate.",
            category: .knowledge,
            acceptedKinds: [.email],
            producesKinds: [.domain, .username],
            requiresAPIKey: false,
            isLive: true,
            symbol: "envelope.badge.fill"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let (local, domain) = EmailIntel.parts(of: entity.label) else {
            throw PluginError.unsupportedEntity
        }
        var result = PluginResult()
        var raw: [String] = ["local=\(local)", "domain=\(domain)"]

        let base = EmailIntel.baseLocal(local)
        let isFree = InfraFilter.isFreeWebmail(domain)
        let isDisposable = EmailIntel.disposableProviders.contains(domain)
        let isRole = EmailIntel.roleAccounts.contains(base)

        result.inputAttributes.append(.init(key: "Local part", value: local, source: "Email Intelligence"))
        result.inputAttributes.append(.init(key: "Domain", value: domain, source: "Email Intelligence"))
        let providerType = isDisposable ? "Disposable / throwaway"
                          : isFree ? "Free webmail"
                          : isRole ? "Corporate (role mailbox)"
                          : "Corporate / private"
        result.inputAttributes.append(.init(key: "Provider type", value: providerType, source: "Email Intelligence"))
        if isDisposable {
            result.inputAttributes.append(.init(key: "Disposable", value: "Yes", kind: .boolean, source: "Email Intelligence"))
        }
        if isRole {
            result.inputAttributes.append(.init(key: "Role account", value: "Yes (\(base))", kind: .boolean, source: "Email Intelligence"))
        }

        // Sub-address ("+tag") detection.
        if local.contains("+"), let tag = local.split(separator: "+", maxSplits: 1).last {
            result.inputAttributes.append(.init(key: "Sub-address tag", value: String(tag), source: "Email Intelligence"))
        }

        // Gmail normalisation: dots are ignored and "+tag" is stripped by Google.
        if domain == "gmail.com" || domain == "googlemail.com" {
            let canonical = base.replacingOccurrences(of: ".", with: "") + "@gmail.com"
            if canonical != entity.label.lowercased() {
                result.inputAttributes.append(.init(key: "Gmail canonical", value: canonical, source: "Email Intelligence"))
            }
        }

        // Domain pivot — unlocks WHOIS / DNS / SSL-CT / etc. Skip for disposable
        // noise AND for free webmail (expanding gmail.com/outlook.com just pulls in
        // the provider's whole infrastructure — useless). The domain stays as an
        // attribute above; it just doesn't become an expandable node.
        if !isDisposable && !isFree {
            result.entities.append(.init(
                kind: .domain, label: domain, subtitle: "Email domain",
                confidence: 0.95, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // Username pivot — unlocks GitHub / Reddit / Mastodon / Bluesky / etc.
        // Only meaningful for personal mailboxes (not role accounts, not free-provider noise like "john.doe").
        if !isRole, base.count >= 3 {
            let confidence = isFree ? 0.45 : 0.35
            result.entities.append(.init(
                kind: .username, label: base, subtitle: "Derived from email local part",
                confidence: confidence, linkKind: .hasUsername, linkDirection: .fromInput
            ))
        }

        // MX → mail host classification.
        let mx = await MXLookup.hosts(for: domain, context: context)
        if mx.isEmpty {
            result.inputAttributes.append(.init(key: "Deliverable", value: "No MX record (domain cannot receive mail)", source: "Email Intelligence"))
        } else {
            raw.append("MX=" + mx.joined(separator: ","))
            if let host = EmailIntel.mailHost(forMX: mx) {
                result.inputAttributes.append(.init(key: "Mail host", value: host, source: "Email Intelligence (MX)"))
            }
            result.inputAttributes.append(.init(key: "MX records", value: mx.prefix(3).joined(separator: ", "), source: "Email Intelligence (MX)"))
        }

        result.rawExcerpt = raw.joined(separator: "\n")
        return result
    }
}
