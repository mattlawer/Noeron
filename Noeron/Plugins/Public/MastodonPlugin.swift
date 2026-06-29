//
//  MastodonPlugin.swift
//  Noeron
//
//  Mastodon (keyless): fediverse profile, home instance and linked fields.
//

import Foundation

struct MastodonPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "mastodon", name: "Mastodon",
              summary: "Fediverse profile, home instance and linked fields.",
              category: .social, acceptedKinds: [.username, .socialProfile],
              producesKinds: [.person, .domain],
              requiresAPIKey: false,
              docURL: "https://docs.joinmastodon.org/api", isLive: true, symbol: "number")
    }

    private struct Account: Decodable {
        let username: String?; let display_name: String?; let note: String?; let url: String?
        let followers_count: Int?
        let fields: [Field]?
        struct Field: Decodable { let name: String?; let value: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        // Parse user@instance (default to mastodon.social).
        let raw = entity.label.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
        let user = parts.first ?? raw
        let instance = parts.count > 1 ? parts[1] : "mastodon.social"

        var comps = URLComponents(string: "https://\(instance)/api/v1/accounts/lookup")!
        comps.queryItems = [.init(name: "acct", value: user)]
        let (data, http) = try await context.get(comps.url!)
        guard http.statusCode == 200, let acct = try? JSONDecoder().decode(Account.self, from: data) else {
            return PluginResult(rawExcerpt: "Mastodon HTTP \(http.statusCode) on \(instance)")
        }
        var result = PluginResult(rawExcerpt: "Mastodon @\(user)@\(instance)")
        if let followers = acct.followers_count { result.inputAttributes.append(.init(key: "Followers", value: followers.formatted(), kind: .number, source: "Mastodon")) }

        result.entities.append(.init(kind: .domain, label: instance.lowercased(), subtitle: "Home instance",
                                     confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        if let name = acct.display_name, !name.isEmpty {
            result.entities.append(.init(kind: .person, label: name, subtitle: "@\(user)@\(instance)",
                                         confidence: 0.6, sourceURL: acct.url ?? "", linkKind: .hasUsername, linkDirection: .toInput))
        }
        // Linked fields often carry a website/handle.
        let blob = ([acct.note] + (acct.fields ?? []).map { $0.value }).compactMap { $0 }.joined(separator: " ")
        for ex in EntityExtractor.extract(from: blob) where ex.kind == .domain || ex.kind == .url {
            result.entities.append(.init(kind: ex.kind, label: ex.value, subtitle: "Linked on Mastodon",
                                         confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        return result
    }
}
