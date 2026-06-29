//
//  TelegramPlugin.swift
//  Noeron
//
//  Telegram (Bot API getChat): resolve a public @username / channel. Bot token required.
//

import Foundation

struct TelegramPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "telegram", name: "Telegram",
              summary: "Resolve a public @username / channel via the Bot API.",
              category: .social, acceptedKinds: [.username],
              producesKinds: [.url],
              requiresAPIKey: true,
              credentialFields: [.init(key: "telegram.botToken", label: "Bot Token")],
              docURL: "https://core.telegram.org/bots/api", isLive: true, symbol: "paperplane")
    }

    private struct Resp: Decodable {
        let ok: Bool?; let result: Chat?
        struct Chat: Decodable { let id: Int?; let title: String?; let username: String?; let type: String?; let description: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let token = context.credential("telegram.botToken") else { throw PluginError.missingCredentials("Telegram bot token") }
        let handle = entity.label.replacingOccurrences(of: "@", with: "")
        let url = URL(string: "https://api.telegram.org/bot\(token)/getChat?chat_id=@\(handle.pathEncoded)")!
        let (data, _) = try await context.get(url)
        let resp = try decode(Resp.self, data)
        guard resp.ok == true, let chat = resp.result else {
            return PluginResult(rawExcerpt: "Telegram: @\(handle) not resolvable via Bot API")
        }
        var result = PluginResult(rawExcerpt: "Telegram chat \(chat.type ?? "")")
        if let title = chat.title { result.inputAttributes.append(.init(key: "Title", value: title, source: "Telegram")) }
        if let desc = chat.description { result.inputAttributes.append(.init(key: "Description", value: desc, source: "Telegram")) }
        result.entities.append(.init(kind: .url, label: "https://t.me/\(handle)", subtitle: chat.type ?? "Telegram",
                                     confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
        return result
    }
}
