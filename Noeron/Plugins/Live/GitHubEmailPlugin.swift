//
//  GitHubEmailPlugin.swift
//  Noeron
//
//  Keyless: searches public commits authored with an email to reveal the GitHub
//  username, real name and repositories behind it. A token raises the rate limit.
//

import Foundation

struct GitHubEmailPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "github-email",
            name: "GitHub (commit email)",
            summary: "Searches public commits authored with this email to reveal the GitHub username, real name and repositories behind it. Keyless (low rate limit); a token raises it.",
            category: .social,
            acceptedKinds: [.email],
            producesKinds: [.username, .person, .url],
            requiresAPIKey: false,
            credentialFields: [.init(key: "github.token", label: "Personal Access Token", hint: "Optional — raises rate limit", optional: true)],
            docURL: "https://docs.github.com/rest/search/search#search-commits",
            isLive: true,
            symbol: "chevron.left.forwardslash.chevron.right"
        )
    }

    private struct Search: Decodable {
        let items: [Item]?
        struct Item: Decodable {
            let commit: Commit?
            let author: Author?
            let repository: Repo?
            struct Commit: Decodable { let author: CommitAuthor?; struct CommitAuthor: Decodable { let name: String? } }
            struct Author: Decodable { let login: String?; let html_url: String? }
            struct Repo: Decodable { let full_name: String?; let html_url: String? }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard EmailIntel.parts(of: entity.label) != nil else { throw PluginError.unsupportedEntity }
        var comps = URLComponents(string: "https://api.github.com/search/commits")!
        comps.queryItems = [.init(name: "q", value: "author-email:\(entity.label)"),
                            .init(name: "per_page", value: "20")]
        guard let url = comps.url else { throw PluginError.unsupportedEntity }

        var headers = ["Accept": "application/vnd.github.cloak-preview+json"]
        if let token = context.credential("github.token") { headers["Authorization"] = "Bearer \(token)" }

        let (data, http) = try await context.get(url, headers: headers)
        guard http.statusCode == 200 else {
            if http.statusCode == 403 || http.statusCode == 429 { throw PluginError.rateLimited }
            return PluginResult(rawExcerpt: "GitHub commit search HTTP \(http.statusCode)")
        }
        guard let search = try? JSONDecoder().decode(Search.self, from: data), let items = search.items, !items.isEmpty else {
            return PluginResult(rawExcerpt: "No public commits for this email")
        }

        var result = PluginResult(rawExcerpt: "GitHub: \(items.count) commits matched")
        var seenLogins = Set<String>()
        var seenNames = Set<String>()
        var seenRepos = Set<String>()
        for item in items {
            if let login = item.author?.login, seenLogins.insert(login).inserted {
                result.entities.append(.init(
                    kind: .username, label: login, subtitle: "GitHub account (commit author)",
                    confidence: 0.85, sourceURL: item.author?.html_url ?? "https://github.com/\(login)",
                    linkKind: .hasUsername, linkDirection: .fromInput
                ))
            }
            if let name = item.commit?.author?.name, !name.isEmpty, seenNames.insert(name.lowercased()).inserted {
                result.entities.append(.init(
                    kind: .person, label: name, subtitle: "Git commit author name",
                    confidence: 0.6, linkKind: .hasEmail, linkDirection: .toInput
                ))
            }
            if let repo = item.repository?.full_name, seenRepos.insert(repo.lowercased()).inserted, seenRepos.count <= 8 {
                result.entities.append(.init(
                    kind: .url, label: item.repository?.html_url ?? "https://github.com/\(repo)",
                    subtitle: "Repo with commits by this email",
                    confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
                ))
            }
        }
        return result
    }
}
