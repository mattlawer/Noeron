//
//  VirusTotalPlugin.swift
//  Noeron
//
//  VirusTotal v3: reputation and passive DNS resolutions for domains and IPs. Key required.
//

import Foundation

struct VirusTotalPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "virustotal", name: "VirusTotal",
              summary: "Reputation and passive DNS resolutions for domains and IPs.",
              category: .threat, acceptedKinds: [.domain, .ipAddress],
              producesKinds: [.ipAddress, .domain],
              requiresAPIKey: true,
              credentialFields: [.init(key: "vt.apiKey", label: "VirusTotal API Key")],
              docURL: "https://docs.virustotal.com/reference", isLive: true, symbol: "shield.lefthalf.filled")
    }

    private struct Obj: Decodable {
        let data: DataObj?
        struct DataObj: Decodable { let attributes: Attr? }
        struct Attr: Decodable {
            let reputation: Int?
            let last_analysis_stats: Stats?
            struct Stats: Decodable { let malicious: Int?; let suspicious: Int?; let harmless: Int?; let undetected: Int? }
        }
    }
    private struct Resolutions: Decodable {
        let data: [Item]?
        struct Item: Decodable { let attributes: Attr? }
        struct Attr: Decodable { let ip_address: String?; let host_name: String? }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let key = context.credential("vt.apiKey") else { throw PluginError.missingCredentials("VirusTotal API key") }
        let headers = ["x-apikey": key]
        let isDomain = entity.kind == .domain
        let base = isDomain ? "domains/\(WhoisPlugin.normalize(entity.label))" : "ip_addresses/\(entity.label)"

        let (objData, http) = try await context.get(URL(string: "https://www.virustotal.com/api/v3/\(base.pathEncoded)")!, headers: headers)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw PluginError.missingCredentials("VirusTotal key rejected") }
            return PluginResult(rawExcerpt: "VirusTotal HTTP \(http.statusCode)")
        }
        let obj = try decode(Obj.self, objData)
        var result = PluginResult(rawExcerpt: String(decoding: objData, as: UTF8.self).truncatedExcerpt())
        if let s = obj.data?.attributes?.last_analysis_stats {
            let flagged = (s.malicious ?? 0) + (s.suspicious ?? 0)
            let total = flagged + (s.harmless ?? 0) + (s.undetected ?? 0)
            result.inputAttributes.append(.init(key: "VT detections", value: "\(flagged) / \(total) engines", source: "VirusTotal"))
        }
        if let rep = obj.data?.attributes?.reputation {
            result.inputAttributes.append(.init(key: "VT reputation", value: String(rep), kind: .number, source: "VirusTotal"))
        }

        // Passive DNS resolutions
        let (resData, resHTTP) = try await context.get(URL(string: "https://www.virustotal.com/api/v3/\(base.pathEncoded)/resolutions?limit=20")!, headers: headers)
        if resHTTP.statusCode == 200, let res = try? JSONDecoder().decode(Resolutions.self, from: resData) {
            for item in (res.data ?? []).prefix(20) {
                if isDomain, let ip = item.attributes?.ip_address {
                    result.entities.append(.init(kind: .ipAddress, label: ip, subtitle: "Passive DNS (VT)",
                                                 confidence: 0.7, linkKind: .resolvesTo, linkDirection: .fromInput))
                } else if !isDomain, let host = item.attributes?.host_name {
                    result.entities.append(.init(kind: .domain, label: host.lowercased(), subtitle: "Passive DNS (VT)",
                                                 confidence: 0.7, linkKind: .resolvesTo, linkDirection: .toInput))
                }
            }
        }
        return result
    }
}
