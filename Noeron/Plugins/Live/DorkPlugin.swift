//
//  DorkPlugin.swift
//  Noeron
//
//  Google-dork search for OSINT / exposure hunting. Runs a curated set of search
//  operators tailored to the selector (domain, email, person, username, company)
//  through a real search API and turns the hits into URL / document nodes.
//
//  Providers (configure either in Settings):
//    • SerpAPI            — one key, simplest.       credential: serpapi.apiKey
//    • Google CSE JSON    — API key + engine id.     credentials: google.cseKey, google.cseCx
//
//  Dorks are well-known public search operators. Use them only against targets you
//  are authorised to investigate, and respect each provider's terms and quota — one
//  run issues several search queries.
//

import Foundation

struct DorkPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "dorks",
            name: "Google Dorks",
            summary: "Runs curated OSINT / leak-hunting Google dorks for a selector via SerpAPI or Google Custom Search and returns the result pages as nodes.",
            category: .threat,
            acceptedKinds: [.domain, .email, .person, .username, .company],
            producesKinds: [.url, .document],
            requiresAPIKey: true,
            credentialFields: [
                .init(key: "serpapi.apiKey", label: "SerpAPI Key", hint: "serpapi.com — simplest, one key"),
                .init(key: "google.cseKey", label: "Google CSE API Key", hint: "Alternative to SerpAPI", optional: true),
                .init(key: "google.cseCx", label: "Google CSE Engine ID (cx)", hint: "Required with the CSE key", optional: true)
            ],
            docURL: "https://serpapi.com/search-api",
            isLive: true,
            symbol: "magnifyingglass.circle.fill"
        )
    }

    // A search provider resolved from configured credentials.
    private enum Provider {
        case serpapi(String)
        case google(key: String, cx: String)
    }

    private func provider(_ context: PluginContext) -> Provider? {
        if let key = context.credential("serpapi.apiKey") { return .serpapi(key) }
        if let key = context.credential("google.cseKey"), let cx = context.credential("google.cseCx") {
            return .google(key: key, cx: cx)
        }
        return nil
    }

    // Auto-discovery is allowed when EITHER provider is configured.
    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool {
        metadata.acceptedKinds.contains(entity.kind) && provider(context) != nil
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let provider = provider(context) else {
            throw PluginError.missingCredentials("SerpAPI key, or Google CSE key + engine id")
        }
        let dorks = Self.dorks(for: entity.kind, target: entity.label)
        guard !dorks.isEmpty else { return .empty }

        let ctx = context
        // Bounded concurrency to stay within search-API rate limits/quota.
        let batches: [[Dork]] = stride(from: 0, to: dorks.count, by: 3).map {
            Array(dorks[$0..<min($0 + 3, dorks.count)])
        }

        var result = PluginResult()
        var seen = Set<String>()
        var ranQueries = 0

        for batch in batches {
            let hits = await withTaskGroup(of: (Dork, [Hit]).self) { group -> [(Dork, [Hit])] in
                for dork in batch {
                    group.addTask { (dork, await Self.search(dork.query, provider: provider, context: ctx)) }
                }
                var out: [(Dork, [Hit])] = []
                for await r in group { out.append(r) }
                return out
            }
            for (dork, hitList) in hits {
                ranQueries += 1
                for hit in hitList.prefix(4) {
                    guard let link = hit.link, seen.insert(link).inserted, seen.count <= 30 else { continue }
                    let isFile = Self.looksLikeFile(link)
                    var attrs: [EntityAttribute] = []
                    if let t = hit.title { attrs.append(.init(key: "Title", value: t, source: "Google Dorks")) }
                    // Why it matched: the search query + the engine's snippet (the
                    // context the term appeared in — it may be in cached/older content
                    // or metadata, not necessarily visible on the live page).
                    attrs.append(.init(key: "Matched query", value: dork.query, source: "Google Dorks"))
                    if let s = hit.snippet, !s.isEmpty {
                        attrs.append(.init(key: "Why matched", value: s, source: "Google Dorks"))
                    }
                    result.entities.append(.init(
                        kind: isFile ? .document : .url,
                        label: link,
                        subtitle: "Dork: \(dork.label)",
                        confidence: 0.4,
                        attributes: attrs,
                        sourceURL: link,
                        linkKind: .mentions, linkDirection: .toInput
                    ))
                }
            }
        }
        result.inputAttributes.append(.init(key: "Dork hits", value: "\(seen.count) results from \(ranQueries) queries", source: "Google Dorks"))
        result.rawExcerpt = "Ran \(ranQueries) dorks, \(seen.count) unique results for \(entity.label)"
        return result
    }

    // MARK: Search providers

    private struct Hit { let title: String?; let link: String?; let snippet: String? }

    private struct SerpResponse: Decodable {
        let organic_results: [Org]?
        struct Org: Decodable { let title: String?; let link: String?; let snippet: String? }
    }
    private struct GoogleResponse: Decodable {
        let items: [Item]?
        struct Item: Decodable { let title: String?; let link: String?; let snippet: String? }
    }

    private static func search(_ query: String, provider: Provider, context: PluginContext) async -> [Hit] {
        switch provider {
        case .serpapi(let key):
            var c = URLComponents(string: "https://serpapi.com/search.json")!
            c.queryItems = [.init(name: "engine", value: "google"), .init(name: "q", value: query),
                            .init(name: "num", value: "10"), .init(name: "api_key", value: key)]
            guard let url = c.url, let resp = try? await context.getJSON(SerpResponse.self, from: url) else { return [] }
            return (resp.organic_results ?? []).map { Hit(title: $0.title, link: $0.link, snippet: $0.snippet) }
        case .google(let key, let cx):
            var c = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
            c.queryItems = [.init(name: "key", value: key), .init(name: "cx", value: cx),
                            .init(name: "q", value: query), .init(name: "num", value: "10")]
            guard let url = c.url, let resp = try? await context.getJSON(GoogleResponse.self, from: url) else { return [] }
            return (resp.items ?? []).map { Hit(title: $0.title, link: $0.link, snippet: $0.snippet) }
        }
    }

    private static func looksLikeFile(_ url: String) -> Bool {
        let lower = url.lowercased()
        return [".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv", ".sql", ".log",
                ".txt", ".env", ".bak", ".old", ".zip", ".json", ".xml"].contains { lower.contains($0) }
    }

    // MARK: Dork catalogue

    struct Dork { let label: String; let query: String }

    /// Curated OSINT / exposure dorks per selector type. `q(target)` quotes the value.
    static func dorks(for kind: EntityKind, target raw: String) -> [Dork] {
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = "\"\(target)\""
        switch kind {
        case .domain:
            let d = WhoisPlugin.normalize(target)
            return [
                .init(label: "Open directories", query: "site:\(d) intitle:\"index of\""),
                .init(label: "Config & secret files", query: "site:\(d) ext:env | ext:ini | ext:yml | ext:cfg | ext:conf"),
                .init(label: "Database & backups", query: "site:\(d) ext:sql | ext:bak | ext:old | ext:backup"),
                .init(label: "Documents", query: "site:\(d) ext:pdf | ext:doc | ext:xls | ext:csv"),
                .init(label: "Login / admin panels", query: "site:\(d) inurl:login | inurl:admin | inurl:signin | inurl:portal"),
                .init(label: "Credentials in text", query: "site:\(d) intext:password | intext:\"api_key\" | intext:secret"),
                .init(label: "Subdomains", query: "site:*.\(d) -www"),
                .init(label: "Exposed on cloud buckets", query: "site:s3.amazonaws.com | site:blob.core.windows.net | site:storage.googleapis.com \"\(d)\""),
                .init(label: "Code & paste mentions", query: "\"\(d)\" site:github.com | site:gitlab.com | site:pastebin.com")
            ]
        case .email:
            return [
                .init(label: "General exposure", query: q),
                .init(label: "Paste-site leaks", query: "\(q) site:pastebin.com | site:ghostbin.com | site:throwbin.io"),
                .init(label: "Leaked lists/files", query: "\(q) filetype:txt | filetype:csv | filetype:log | filetype:xls"),
                .init(label: "Code mentions", query: "\(q) site:github.com | site:gitlab.com"),
                .init(label: "Docs & boards", query: "\(q) site:scribd.com | site:trello.com | site:docs.google.com"),
                .init(label: "With password context", query: "\(q) intext:password")
            ]
        case .person:
            return [
                .init(label: "Professional profile", query: "\(q) site:linkedin.com"),
                .init(label: "Resume / CV", query: "\(q) (filetype:pdf | filetype:doc) (resume | cv | curriculum)"),
                .init(label: "Contact details", query: "\(q) (intext:\"@gmail.com\" | intext:phone | intext:email)"),
                .init(label: "Social presence", query: "\(q) site:twitter.com | site:facebook.com | site:instagram.com"),
                .init(label: "Code / projects", query: "\(q) site:github.com"),
                .init(label: "Documents", query: "\(q) filetype:pdf | filetype:doc | filetype:pptx")
            ]
        case .username:
            return [
                .init(label: "General exposure", query: q),
                .init(label: "Paste-site leaks", query: "\(q) site:pastebin.com"),
                .init(label: "Code mentions", query: "\(q) site:github.com | site:gitlab.com"),
                .init(label: "Forums & social", query: "\(q) site:reddit.com | site:twitter.com | site:keybase.io"),
                .init(label: "Breach/dump context", query: "\(q) intext:password | intext:dump | intext:leak")
            ]
        case .company:
            return [
                .init(label: "Confidential documents", query: "\(q) (filetype:pdf | filetype:xls | filetype:doc) (confidential | internal | \"not for distribution\")"),
                .init(label: "Employee / contact lists", query: "\(q) (filetype:xls | filetype:csv) (email | phone | employees)"),
                .init(label: "Professional profiles", query: "\(q) site:linkedin.com"),
                .init(label: "Cloud bucket exposure", query: "site:s3.amazonaws.com | site:blob.core.windows.net \(q)"),
                .init(label: "Boards & paste leaks", query: "\(q) site:trello.com | site:pastebin.com | site:github.com")
            ]
        default:
            return [.init(label: "General exposure", query: q)]
        }
    }
}
