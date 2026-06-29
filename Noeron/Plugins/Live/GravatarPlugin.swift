//
//  GravatarPlugin.swift
//  Noeron
//
//  Keyless Gravatar public-profile lookup for an email (MD5 hash): display name,
//  avatar, location, linked social accounts and websites.
//

import Foundation

struct GravatarPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "gravatar",
            name: "Gravatar",
            summary: "Looks up the Gravatar public profile for an email (MD5 hash): display name, avatar, location, linked social accounts and websites. No key.",
            category: .social,
            acceptedKinds: [.email],
            producesKinds: [.person, .username, .url, .location],
            requiresAPIKey: false,
            docURL: "https://docs.gravatar.com/api/profiles/",
            isLive: true,
            symbol: "person.crop.circle.badge.checkmark"
        )
    }

    private struct Root: Decodable { let entry: [Entry]? }
    private struct Entry: Decodable {
        let profileUrl: String?
        let preferredUsername: String?
        let displayName: String?
        let thumbnailUrl: String?
        let aboutMe: String?
        let currentLocation: String?
        let name: Name?
        let photos: [Photo]?
        let accounts: [Account]?
        let urls: [Link]?
        struct Name: Decodable { let formatted: String? }
        struct Photo: Decodable { let value: String?; let type: String? }
        struct Account: Decodable {
            let domain: String?; let display: String?; let url: String?
            let username: String?; let shortname: String?; let verified: String?
        }
        struct Link: Decodable { let value: String?; let title: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let normalized = entity.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = EmailIntel.md5Hex(normalized)
        guard let url = URL(string: "https://en.gravatar.com/\(hash).json") else { throw PluginError.unsupportedEntity }

        let (data, http) = try await context.get(url)
        // 404 = no Gravatar; 200 = profile JSON. Anything else: non-fatal.
        guard http.statusCode == 200 else {
            return PluginResult(rawExcerpt: http.statusCode == 404 ? "No Gravatar profile" : "Gravatar HTTP \(http.statusCode)")
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data), let e = root.entry?.first else {
            return PluginResult(rawExcerpt: "Gravatar: unparseable profile")
        }

        var result = PluginResult(rawExcerpt: String(decoding: data, as: UTF8.self).truncatedExcerpt())
        let profileURL = e.profileUrl ?? "https://gravatar.com/\(hash)"
        result.inputAttributes.append(.init(key: "Gravatar profile", value: profileURL, kind: .url, source: "Gravatar"))
        if let avatar = e.thumbnailUrl ?? e.photos?.first?.value {
            result.inputAttributes.append(.init(key: "Avatar", value: avatar, kind: .url, source: "Gravatar"))
        }
        if let about = e.aboutMe, !about.isEmpty {
            result.inputAttributes.append(.init(key: "About", value: about, source: "Gravatar"))
        }

        // Only emit a Person when we have an actual name — not when the "display
        // name" is just the handle (that's already captured as the username below,
        // and emitting it as a Person creates a duplicate person for one individual).
        let realName = e.name?.formatted ?? e.displayName
        let handleLower = (e.preferredUsername ?? "").lowercased()
        if let name = realName, !name.isEmpty,
           name.lowercased() != handleLower,
           name.contains(" ") {
            result.entities.append(.init(
                kind: .person, label: name, subtitle: "Gravatar profile",
                confidence: 0.75, sourceURL: profileURL,
                linkKind: .hasEmail, linkDirection: .toInput
            ))
        }
        if let handle = e.preferredUsername, !handle.isEmpty {
            result.entities.append(.init(
                kind: .username, label: handle, subtitle: "Gravatar username",
                confidence: 0.7, sourceURL: profileURL,
                linkKind: .hasUsername, linkDirection: .fromInput
            ))
        }
        if let loc = e.currentLocation, !loc.isEmpty {
            result.entities.append(.init(
                kind: .location, label: loc, subtitle: "Self-reported (Gravatar)",
                confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        // Linked social accounts → username pivots (strong: user verified them on Gravatar).
        for acct in e.accounts ?? [] {
            let service = acct.shortname ?? acct.domain ?? "account"
            if let u = acct.username, !u.isEmpty {
                result.entities.append(.init(
                    kind: .username, label: u, subtitle: "\(service) (linked on Gravatar)",
                    confidence: 0.7, sourceURL: acct.url ?? "",
                    linkKind: .relatedTo, linkDirection: .fromInput
                ))
            } else if let link = acct.url, let u = URL(string: link) {
                result.entities.append(.init(
                    kind: .url, label: u.absoluteString, subtitle: "\(service) (linked on Gravatar)",
                    confidence: 0.6, linkKind: .relatedTo, linkDirection: .fromInput
                ))
            }
        }
        // Free-form linked websites.
        for link in e.urls ?? [] {
            guard let value = link.value, let host = URL(string: value)?.host else { continue }
            result.entities.append(.init(
                kind: .domain, label: host.lowercased(),
                subtitle: link.title?.isEmpty == false ? "\(link.title!) (Gravatar)" : "Linked on Gravatar",
                confidence: 0.55, sourceURL: value, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        return result
    }
}
