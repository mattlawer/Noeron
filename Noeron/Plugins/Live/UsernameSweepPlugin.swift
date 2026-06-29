//
//  UsernameSweepPlugin.swift
//  Noeron
//
//  ONE keyless plugin that checks whether a username exists across many public
//  services — social networks, dev platforms, media, mobile apps and creator/
//  dating sites — instead of dozens of near-identical "is @x on site Y" plugins.
//  Each site is a row in a data catalogue, so adding coverage is a one-line edit,
//  not a new plugin.
//
//  Detection is the same approach Sherlock / WhatsMyName use: request the profile
//  URL and decide from the HTTP status or a marker string in the body. Every check
//  is best-effort and non-fatal; a site that blocks bots or rate-limits is simply
//  skipped. Sites that already have a dedicated rich plugin (GitHub, Reddit,
//  Mastodon, Bluesky, Gravatar) are intentionally excluded to avoid duplication.
//

import Foundation

struct UsernameSweepPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "username-sweep",
            name: "Username Sweep",
            summary: "Checks one username across ~40 public sites (social, dev, media, gaming, mobile apps, creator/dating) and reports where a profile exists. Keyless, best-effort.",
            category: .social,
            acceptedKinds: [.username, .socialProfile],
            producesKinds: [.url],
            requiresAPIKey: false,
            isLive: true,
            symbol: "person.2.wave.2.fill"
        )
    }

    // MARK: Detection model

    enum Method: Sendable {
        case status                 // HTTP 200 ⇒ exists, 404 ⇒ not
        case notFound(String)       // 200 and body does NOT contain marker ⇒ exists
        case found(String)          // 200 and body contains marker ⇒ exists
    }

    struct Site: Sendable {
        let name: String
        let category: String
        let url: String             // profile URL template; "{u}" → username
        let method: Method
        func profileURL(_ username: String) -> String {
            url.replacingOccurrences(of: "{u}", with: username.pathEncoded)
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let username = entity.label
            .trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.count >= 2, !username.contains(" ") else { throw PluginError.unsupportedEntity }

        let ctx = context
        let sites = Self.catalogue
        let limit = 10

        // Bounded-concurrency sweep with a false-positive control: a site only
        // counts when the real username passes its detector AND a known-nonexistent
        // sentinel FAILS it. Sites that "exist" for everyone (SPAs that always
        // return 200, soft-404 pages, bot walls) match the sentinel too and are
        // discarded — eliminating the bulk of username-sweep false positives.
        let hits: [Site] = await withTaskGroup(of: Site?.self) { group in
            var iterator = sites.makeIterator()
            var inFlight = 0
            func addNext() {
                guard let site = iterator.next() else { return }
                group.addTask {
                    async let real = Self.check(site, username: username, context: ctx)
                    async let control = Self.check(site, username: Self.sentinel, context: ctx)
                    let (r, c) = await (real, control)
                    return (r && !c) ? site : nil
                }
                inFlight += 1
            }
            for _ in 0..<limit { addNext() }
            var found: [Site] = []
            while inFlight > 0, let outcome = await group.next() {
                inFlight -= 1
                if let site = outcome { found.append(site) }
                addNext()
            }
            return found
        }

        var result = PluginResult(rawExcerpt: "Username sweep: \(hits.count)/\(sites.count) sites matched for \(username)")
        result.inputAttributes.append(.init(key: "Profiles found", value: "\(hits.count) of \(sites.count) sites checked", kind: .number, source: "Username Sweep"))
        if !hits.isEmpty {
            let summary = hits.map(\.name).sorted().joined(separator: ", ")
            result.inputAttributes.append(.init(key: "Found on", value: summary, source: "Username Sweep"))
        }
        for site in hits.sorted(by: { $0.name < $1.name }) {
            result.entities.append(.init(
                kind: .url, label: site.profileURL(username),
                subtitle: "\(site.name) · \(site.category)",
                confidence: 0.7,
                attributes: [.init(key: "Service", value: site.name, source: "Username Sweep"),
                             .init(key: "Category", value: site.category, source: "Username Sweep")],
                sourceURL: site.profileURL(username),
                linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        return result
    }

    private static func check(_ site: Site, username: String, context: PluginContext) async -> Bool {
        guard let url = URL(string: site.profileURL(username)),
              let (data, http) = try? await context.get(url, timeout: 10) else { return false }
        switch site.method {
        case .status:
            return http.statusCode == 200
        case .notFound(let marker):
            return http.statusCode == 200 && !String(decoding: data, as: UTF8.self).contains(marker)
        case .found(let marker):
            return http.statusCode == 200 && String(decoding: data, as: UTF8.self).contains(marker)
        }
    }

    /// A username implausible enough that no real account should exist for it,
    /// used as the negative control to detect unreliable (always-200) detectors.
    static let sentinel = "noeronqa7zx39kvw2"

    // MARK: Site catalogue (edit this list to add coverage — no new plugin needed)

    static let catalogue: [Site] = [
        // Developer / tech
        .init(name: "GitLab",      category: "Dev",     url: "https://gitlab.com/{u}",                     method: .status),
        .init(name: "Bitbucket",   category: "Dev",     url: "https://bitbucket.org/{u}/",                 method: .status),
        .init(name: "Replit",      category: "Dev",     url: "https://replit.com/@{u}",                    method: .status),
        .init(name: "Dev.to",      category: "Dev",     url: "https://dev.to/{u}",                         method: .status),
        .init(name: "Keybase",     category: "Dev",     url: "https://keybase.io/{u}",                     method: .status),
        .init(name: "Docker Hub",  category: "Dev",     url: "https://hub.docker.com/u/{u}",               method: .status),
        .init(name: "PyPI",        category: "Dev",     url: "https://pypi.org/user/{u}/",                 method: .status),
        .init(name: "npm",         category: "Dev",     url: "https://www.npmjs.com/~{u}",                 method: .status),
        .init(name: "CodePen",     category: "Dev",     url: "https://codepen.io/{u}",                     method: .status),
        .init(name: "Hacker News", category: "Dev",     url: "https://news.ycombinator.com/user?id={u}",   method: .notFound("No such user")),

        // Social
        .init(name: "Telegram",    category: "Social",  url: "https://t.me/{u}",                           method: .found("tgme_page_title")),
        .init(name: "VK",          category: "Social",  url: "https://vk.com/{u}",                         method: .status),
        .init(name: "Tumblr",      category: "Social",  url: "https://{u}.tumblr.com",                     method: .status),
        .init(name: "Pinterest",   category: "Social",  url: "https://www.pinterest.com/{u}/",             method: .status),
        .init(name: "Linktree",    category: "Social",  url: "https://linktr.ee/{u}",                      method: .status),
        .init(name: "about.me",    category: "Social",  url: "https://about.me/{u}",                       method: .status),
        .init(name: "Patreon",     category: "Social",  url: "https://www.patreon.com/{u}",                method: .status),
        .init(name: "Gravatar",    category: "Social",  url: "https://gravatar.com/{u}",                   method: .status),

        // Media / content / music
        .init(name: "Medium",      category: "Media",   url: "https://medium.com/@{u}",                    method: .status),
        .init(name: "YouTube",     category: "Media",   url: "https://www.youtube.com/@{u}",               method: .status),
        .init(name: "Vimeo",       category: "Media",   url: "https://vimeo.com/{u}",                      method: .status),
        .init(name: "SoundCloud",  category: "Music",   url: "https://soundcloud.com/{u}",                 method: .status),
        .init(name: "Bandcamp",    category: "Music",   url: "https://{u}.bandcamp.com",                   method: .status),
        .init(name: "Last.fm",     category: "Music",   url: "https://www.last.fm/user/{u}",               method: .status),
        .init(name: "Flickr",      category: "Photo",   url: "https://www.flickr.com/people/{u}",          method: .status),
        .init(name: "Imgur",       category: "Photo",   url: "https://imgur.com/user/{u}",                 method: .status),
        .init(name: "Slideshare",  category: "Media",   url: "https://www.slideshare.net/{u}",             method: .status),

        // Gaming
        .init(name: "Steam",       category: "Gaming",  url: "https://steamcommunity.com/id/{u}",          method: .notFound("The specified profile could not be found")),
        .init(name: "Lichess",     category: "Gaming",  url: "https://lichess.org/@/{u}",                  method: .status),
        .init(name: "Chess.com",   category: "Gaming",  url: "https://www.chess.com/member/{u}",           method: .status),
        .init(name: "Speedrun",    category: "Gaming",  url: "https://www.speedrun.com/user/{u}",          method: .status),
        .init(name: "Wattpad",     category: "Content", url: "https://www.wattpad.com/user/{u}",           method: .status),

        // Mobile apps / payments
        .init(name: "Cash App",    category: "Mobile",  url: "https://cash.app/${u}",                      method: .status),
        .init(name: "Venmo",       category: "Mobile",  url: "https://venmo.com/u/{u}",                    method: .status),
        .init(name: "Snapchat",    category: "Mobile",  url: "https://www.snapchat.com/add/{u}",           method: .status),
        .init(name: "Kik",         category: "Mobile",  url: "https://kik.me/{u}",                         method: .status),

        // Creator / dating / adult (public profiles only)
        .init(name: "OnlyFans",    category: "Creator", url: "https://onlyfans.com/{u}",                   method: .status),
        .init(name: "Fansly",      category: "Creator", url: "https://fansly.com/{u}",                     method: .status),
        .init(name: "Chaturbate",  category: "Adult",   url: "https://chaturbate.com/{u}/",                method: .status),
        .init(name: "Pornhub",     category: "Adult",   url: "https://www.pornhub.com/users/{u}",          method: .status)
    ]
}
