//
//  EmailAccountExistencePlugin.swift
//  Noeron
//
//  Keyless, holehe-style account-existence checks: services that leak whether an
//  email is registered via lookup/registration endpoints (Firefox, Duolingo,
//  Spotify). Best-effort; only confident hits are reported.
//

import Foundation

struct EmailAccountExistencePlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "email-accounts",
            name: "Account Existence",
            summary: "Checks whether the email is registered on public services that leak existence via lookup/registration endpoints (Firefox, Duolingo, Spotify). Keyless and best-effort; only confident hits are reported.",
            category: .social,
            acceptedKinds: [.email],
            producesKinds: [.username, .person, .url, .location],
            requiresAPIKey: false,
            isLive: true,
            symbol: "checklist"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard EmailIntel.parts(of: entity.label) != nil else { throw PluginError.unsupportedEntity }
        var result = PluginResult()
        var log: [String] = []

        await checkFirefox(entity.label, context: context, into: &result, log: &log)
        await checkDuolingo(entity.label, context: context, into: &result, log: &log)
        await checkSpotify(entity.label, context: context, into: &result, log: &log)

        result.rawExcerpt = log.isEmpty ? "No account-existence signals" : log.joined(separator: "\n")
        return result
    }

    private func registered(_ service: String, url: String, into result: inout PluginResult) {
        result.inputAttributes.append(.init(key: "Registered: \(service)", value: "Yes", kind: .boolean, source: "Account Existence"))
        if let u = URL(string: url) {
            result.entities.append(.init(
                kind: .url, label: u.absoluteString, subtitle: "\(service) account exists for this email",
                confidence: 0.75, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
    }

    // Mozilla / Firefox Accounts: POST status → {exists: bool}. Stable, keyless.
    private struct FxStatus: Decodable { let exists: Bool? }
    private func checkFirefox(_ email: String, context: PluginContext, into result: inout PluginResult, log: inout [String]) async {
        guard let url = URL(string: "https://api.accounts.firefox.com/v1/account/status") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Noeron/1.0 (OSINT workspace)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        guard let (data, resp) = try? await context.session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(FxStatus.self, from: data) else { log.append("firefox: error"); return }
        if status.exists == true {
            log.append("firefox: exists")
            registered("Firefox / Mozilla", url: "https://accounts.firefox.com", into: &result)
        } else {
            log.append("firefox: none")
        }
    }

    // Duolingo: public user lookup by email returns username, name, location, streak.
    private struct DuoUsers: Decodable {
        let users: [DuoUser]?
        struct DuoUser: Decodable {
            let username: String?; let name: String?; let location: String?
            let creationDate: Double?; let streak: Int?
        }
    }
    private func checkDuolingo(_ email: String, context: PluginContext, into result: inout PluginResult, log: inout [String]) async {
        var comps = URLComponents(string: "https://www.duolingo.com/2017-06-30/users")!
        comps.queryItems = [.init(name: "email", value: email)]
        guard let url = comps.url,
              let parsed = try? await context.getJSON(DuoUsers.self, from: url),
              let user = parsed.users?.first else { log.append("duolingo: none/error"); return }
        log.append("duolingo: exists")
        result.inputAttributes.append(.init(key: "Registered: Duolingo", value: "Yes", kind: .boolean, source: "Account Existence"))
        if let username = user.username, !username.isEmpty {
            result.entities.append(.init(
                kind: .username, label: username, subtitle: "Duolingo account",
                confidence: 0.8, sourceURL: "https://www.duolingo.com/profile/\(username)",
                linkKind: .hasUsername, linkDirection: .fromInput
            ))
        }
        if let name = user.name, !name.isEmpty {
            result.entities.append(.init(
                kind: .person, label: name, subtitle: "Duolingo display name",
                confidence: 0.55, linkKind: .hasEmail, linkDirection: .toInput
            ))
        }
        if let loc = user.location, !loc.isEmpty {
            result.entities.append(.init(
                kind: .location, label: loc, subtitle: "Self-reported (Duolingo)",
                confidence: 0.45, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        if let created = user.creationDate {
            result.events.append(.init(title: "Duolingo account created",
                                       date: Date(timeIntervalSince1970: created), category: "Account", detail: email))
        }
    }

    // Spotify signup validator: status 20 ⇒ email already in use.
    private struct SpotifyStatus: Decodable { let status: Int? }
    private func checkSpotify(_ email: String, context: PluginContext, into result: inout PluginResult, log: inout [String]) async {
        var comps = URLComponents(string: "https://spclient.wg.spotify.com/signup/public/v1/account")!
        comps.queryItems = [.init(name: "validate", value: "1"), .init(name: "email", value: email)]
        guard let url = comps.url,
              let parsed = try? await context.getJSON(SpotifyStatus.self, from: url) else { log.append("spotify: error"); return }
        if parsed.status == 20 {
            log.append("spotify: exists")
            registered("Spotify", url: "https://open.spotify.com", into: &result)
        } else {
            log.append("spotify: none (status \(parsed.status.map(String.init) ?? "?"))")
        }
    }
}
