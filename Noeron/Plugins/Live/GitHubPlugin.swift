//
//  GitHubPlugin.swift
//  Noeron
//
//  Live GitHub profile enrichment via api.github.com. Works keyless (60 req/hr);
//  add a personal access token in Settings to raise the limit.
//  username → real name · company · blog domain · location · linked Twitter.
//

import Foundation

struct GitHubPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "github",
            name: "GitHub",
            summary: "Resolves a GitHub username to its profile: name, company, blog, location.",
            category: .social,
            acceptedKinds: [.username, .socialProfile],
            producesKinds: [.person, .company, .domain, .location, .username],
            requiresAPIKey: false,
            credentialFields: [.init(key: "github.token", label: "Personal Access Token", hint: "Optional — raises rate limit", optional: true)],
            isLive: true,
            symbol: "chevron.left.forwardslash.chevron.right"
        )
    }

    private struct GHUser: Decodable {
        let login: String?
        let name: String?
        let company: String?
        let blog: String?
        let location: String?
        let bio: String?
        let twitter_username: String?
        let public_repos: Int?
        let followers: Int?
        let html_url: String?
        let created_at: String?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let username = entity.label
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty, let url = URL(string: "https://api.github.com/users/\(username)") else {
            throw PluginError.unsupportedEntity
        }

        var headers = ["Accept": "application/vnd.github+json"]
        if let token = context.credential("github.token") { headers["Authorization"] = "Bearer \(token)" }

        let (data, http) = try await context.get(url, headers: headers)
        guard http.statusCode == 200 else {
            if http.statusCode == 404 { return .empty }
            if http.statusCode == 403 { throw PluginError.rateLimited }
            throw PluginError.network("HTTP \(http.statusCode)")
        }
        guard let user = try? JSONDecoder().decode(GHUser.self, from: data) else {
            throw PluginError.decoding("github user")
        }

        var result = PluginResult(rawExcerpt: String(decoding: data, as: UTF8.self).truncatedExcerpt())
        let profileURL = user.html_url ?? "https://github.com/\(username)"

        result.inputAttributes.append(.init(key: "Profile", value: profileURL, kind: .url, source: "GitHub"))
        if let repos = user.public_repos { result.inputAttributes.append(.init(key: "Public repos", value: String(repos), kind: .number, source: "GitHub")) }
        if let followers = user.followers { result.inputAttributes.append(.init(key: "Followers", value: String(followers), kind: .number, source: "GitHub")) }
        if let bio = user.bio, !bio.isEmpty { result.inputAttributes.append(.init(key: "Bio", value: bio, source: "GitHub")) }

        if let name = user.name, !name.isEmpty {
            result.entities.append(.init(
                kind: .person, label: name, subtitle: "GitHub: @\(username)",
                confidence: 0.7, sourceURL: profileURL,
                linkKind: .hasUsername, linkDirection: .toInput
            ))
        }
        if let company = user.company, !company.isEmpty {
            result.entities.append(.init(
                kind: .company, label: company.replacingOccurrences(of: "@", with: ""),
                subtitle: "Listed on GitHub", confidence: 0.5,
                linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if let blog = user.blog, !blog.isEmpty,
           let host = URL(string: blog.hasPrefix("http") ? blog : "https://\(blog)")?.host {
            result.entities.append(.init(
                kind: .domain, label: host.lowercased(), subtitle: "GitHub blog/website",
                confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if let location = user.location, !location.isEmpty {
            result.entities.append(.init(
                kind: .location, label: location, subtitle: "Self-reported (GitHub)",
                confidence: 0.4, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if let tw = user.twitter_username, !tw.isEmpty {
            result.entities.append(.init(
                kind: .username, label: "@\(tw)", subtitle: "Twitter/X (via GitHub)",
                confidence: 0.6, sourceURL: "https://twitter.com/\(tw)",
                linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if let created = user.created_at,
           let date = ISO8601DateFormatter().date(from: created) {
            result.events.append(.init(title: "GitHub account created: @\(username)", date: date,
                                       category: "Account", detail: "github.com/\(username)"))
        }
        return result
    }
}
