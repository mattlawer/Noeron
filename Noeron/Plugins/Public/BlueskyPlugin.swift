//
//  BlueskyPlugin.swift
//  Noeron
//
//  Bluesky (keyless): AT-Protocol handle, DID and display name.
//

import Foundation

struct BlueskyPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "bluesky", name: "Bluesky",
              summary: "AT-Protocol handle, DID and display name.",
              category: .social, acceptedKinds: [.username, .socialProfile],
              producesKinds: [.person, .domain],
              requiresAPIKey: false,
              docURL: "https://docs.bsky.app", isLive: true, symbol: "cloud")
    }

    private struct Profile: Decodable {
        let did: String?; let handle: String?; let displayName: String?; let description: String?
        let followersCount: Int?; let postsCount: Int?
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let handle = entity.label.replacingOccurrences(of: "@", with: "")
        var comps = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile")!
        comps.queryItems = [.init(name: "actor", value: handle)]
        let (data, http) = try await context.get(comps.url!)
        guard http.statusCode == 200, let p = try? JSONDecoder().decode(Profile.self, from: data) else {
            return PluginResult(rawExcerpt: "Bluesky HTTP \(http.statusCode)")
        }
        var result = PluginResult(rawExcerpt: "Bluesky @\(handle)")
        if let did = p.did { result.inputAttributes.append(.init(key: "DID", value: did, source: "Bluesky")) }
        if let f = p.followersCount { result.inputAttributes.append(.init(key: "Followers", value: f.formatted(), kind: .number, source: "Bluesky")) }
        if let name = p.displayName, !name.isEmpty {
            result.entities.append(.init(kind: .person, label: name, subtitle: "@\(handle)",
                                         confidence: 0.6, sourceURL: "https://bsky.app/profile/\(handle)",
                                         linkKind: .hasUsername, linkDirection: .toInput))
        }
        // A custom handle is itself a domain (e.g. user owns example.com as their handle).
        if handle.contains("."), !handle.hasSuffix(".bsky.social") {
            result.entities.append(.init(kind: .domain, label: handle.lowercased(), subtitle: "Bluesky handle domain",
                                         confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        for ex in EntityExtractor.extract(from: p.description ?? "") where ex.kind == .domain || ex.kind == .url {
            result.entities.append(.init(kind: ex.kind, label: ex.value, subtitle: "Linked on Bluesky",
                                         confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput))
        }
        return result
    }
}
