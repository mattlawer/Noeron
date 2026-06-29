//
//  RedditPlugin.swift
//  Noeron
//
//  Reddit (keyless): public account age and karma for a username.
//

import Foundation

struct RedditPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "reddit", name: "Reddit",
              summary: "Public account age and karma for a username.",
              category: .social, acceptedKinds: [.username],
              producesKinds: [.url],
              requiresAPIKey: false,
              docURL: "https://www.reddit.com/dev/api", isLive: true, symbol: "bubble.left.and.bubble.right")
    }

    private struct About: Decodable {
        let data: DataObj?
        struct DataObj: Decodable {
            let name: String?; let created_utc: Double?; let total_karma: Int?
            let link_karma: Int?; let comment_karma: Int?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let handle = entity.label.replacingOccurrences(of: "u/", with: "").replacingOccurrences(of: "@", with: "")
        let url = URL(string: "https://www.reddit.com/user/\(handle.pathEncoded)/about.json")!
        let (data, http) = try await context.get(url)
        guard http.statusCode == 200, let about = try? JSONDecoder().decode(About.self, from: data), let d = about.data else {
            return PluginResult(rawExcerpt: "Reddit HTTP \(http.statusCode)")
        }
        var result = PluginResult(rawExcerpt: "Reddit u/\(handle)")
        if let karma = d.total_karma { result.inputAttributes.append(.init(key: "Total karma", value: karma.formatted(), kind: .number, source: "Reddit")) }
        if let lk = d.link_karma, let ck = d.comment_karma {
            result.inputAttributes.append(.init(key: "Karma (post/comment)", value: "\(lk) / \(ck)", source: "Reddit"))
        }
        result.entities.append(.init(kind: .url, label: "https://reddit.com/u/\(handle)", subtitle: "Reddit profile",
                                     confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        if let created = d.created_utc {
            result.events.append(.init(title: "Reddit account created: u/\(handle)",
                                       date: Date(timeIntervalSince1970: created), category: "Account"))
        }
        return result
    }
}
