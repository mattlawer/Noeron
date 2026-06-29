//
//  DNSoverHTTPS.swift
//  Noeron
//
//  Shared keyless DNS-over-HTTPS helper (Cloudflare JSON API) used by recon plugins.
//

import Foundation

enum DNSoverHTTPS {
    private struct Resp: Decodable {
        let Answer: [Ans]?
        struct Ans: Decodable { let type: Int; let data: String }
    }
    /// Raw record data strings for a name/type (empty on any error).
    static func query(_ name: String, type: String, context: PluginContext) async -> [String] {
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        comps.queryItems = [.init(name: "name", value: name), .init(name: "type", value: type)]
        guard let url = comps.url,
              let resp = try? await context.getJSON(Resp.self, from: url, headers: ["Accept": "application/dns-json"])
        else { return [] }
        return (resp.Answer ?? []).map { $0.data }
    }
    /// True when the name has at least one A/AAAA record (i.e. is registered & live).
    static func resolves(_ name: String, context: PluginContext) async -> Bool {
        if !(await query(name, type: "A", context: context)).isEmpty { return true }
        return !(await query(name, type: "AAAA", context: context)).isEmpty
    }
}
