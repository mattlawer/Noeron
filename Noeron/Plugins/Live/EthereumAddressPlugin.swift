//
//  EthereumAddressPlugin.swift
//  Noeron
//
//  Keyless Ethereum on-chain intel via the public Blockscout API. Lists the
//  account itself rather than fanning out into related wallets:
//    • balance + USD estimate, contract flag, custom name (ENS)
//    • first activity (single oldest-first query — no block looping)
//    • held tokens (each openable in the explorer)
//    • the last 25 transactions: explorer link, interaction address (+ contract
//      name & decoded function call), amount and any token transferred.
//  Transactions and tokens are emitted as `.document` nodes, so they are listed
//  and clickable but never trigger further crawling.
//

import Foundation

struct EthereumAddressPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "eth-onchain",
            name: "Ethereum On-chain",
            summary: "Balance + USD, ENS, held tokens and the last 25 transactions (with amounts, token transfers, decoded calls and explorer links) for an Ethereum address (Blockscout). Keyless.",
            category: .blockchain,
            acceptedKinds: [.cryptoWallet],
            producesKinds: [.document],
            requiresAPIKey: false,
            parameterFields: [.init(key: "eth.blockscoutBase", label: "Blockscout instance",
                                    hint: "Use any Blockscout-compatible explorer (e.g. an L2).",
                                    placeholder: "https://eth.blockscout.com")],
            docURL: "https://docs.blockscout.com/devs/apis/rest",
            isLive: true,
            symbol: "diamond.fill"
        )
    }

    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool {
        entity.kind == .cryptoWallet && CryptoAddress.chain(of: entity.label) == .ethereum
    }

    private func txExplorer(_ hash: String) -> String { "https://etherscan.io/tx/\(hash)" }

    private struct Address: Decodable {
        let coin_balance: String?
        let exchange_rate: String?
        let is_contract: Bool?
        let ens_domain_name: String?
        let name: String?
    }
    private struct TokenItem: Decodable {
        let value: String?
        let token: Token?
        struct Token: Decodable { let symbol: String?; let name: String?; let address: String?; let decimals: String?; let exchange_rate: String? }
    }
    private struct Txs: Decodable {
        let items: [Item]?
        struct Item: Decodable {
            let hash: String?
            let timestamp: String?
            let value: String?
            let method: String?
            let from: Party?
            let to: Party?
            let decoded_input: Decoded?
            let token_transfers: [TokenTransfer]?
            struct Party: Decodable { let hash: String?; let is_contract: Bool?; let name: String?; let ens_domain_name: String? }
            struct Decoded: Decodable { let method_call: String? }
            struct TokenTransfer: Decodable {
                let token: Tok?; let total: Total?
                struct Tok: Decodable { let symbol: String?; let decimals: String? }
                struct Total: Decodable { let value: String?; let decimals: String? }
            }
        }
    }
    private struct Legacy: Decodable { let result: [Row]?; struct Row: Decodable { let timeStamp: String? } }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let addr = entity.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = context.parameter("eth.blockscoutBase") ?? "https://eth.blockscout.com"
        let base = "\(host)/api/v2/addresses"
        let legacy = "\(host)/api"
        guard CryptoAddress.chain(of: addr) == .ethereum,
              let url = URL(string: "\(base)/\(addr.pathEncoded)") else { throw PluginError.unsupportedEntity }

        let (data, http) = try await context.get(url)
        guard http.statusCode == 200, let a = try? JSONDecoder().decode(Address.self, from: data) else {
            return PluginResult(rawExcerpt: "Ethereum: address not found / HTTP \(http.statusCode)")
        }

        let ethBal = (Double(a.coin_balance ?? "") ?? 0) / 1e18
        var result = PluginResult(rawExcerpt: "ETH \(Self.fmt(ethBal)) balance")
        result.inputAttributes.append(.init(key: "Chain", value: "Ethereum", source: "Blockscout"))
        result.inputAttributes.append(.init(key: "Balance", value: "\(Self.fmt(ethBal)) ETH", source: "Blockscout"))
        result.inputAttributes.append(.init(key: "Type", value: (a.is_contract == true) ? "Contract" : "Wallet (EOA)", source: "Blockscout"))
        if let ens = a.ens_domain_name, !ens.isEmpty {
            result.inputAttributes.append(.init(key: "Custom name (ENS)", value: ens, source: "Blockscout"))
        }
        if let name = a.name, !name.isEmpty {
            result.inputAttributes.append(.init(key: "Label", value: name, source: "Blockscout"))
        }
        result.inputAttributes.append(.init(key: "Explorer", value: "https://etherscan.io/address/\(addr)", kind: .url, source: "Blockscout"))

        var usdTotal = ethBal * (Double(a.exchange_rate ?? "") ?? 0)

        // Held tokens → count, value, and one openable node per token.
        if let turl = URL(string: "\(base)/\(addr.pathEncoded)/token-balances"),
           let tokens = try? await context.getJSON([TokenItem].self, from: turl), !tokens.isEmpty {
            result.inputAttributes.append(.init(key: "Tokens found", value: String(tokens.count), kind: .number, source: "Blockscout"))
            for t in tokens.prefix(25) {
                let dec = Int(t.token?.decimals ?? "18") ?? 18
                let amount = (Double(t.value ?? "") ?? 0) / pow(10, Double(dec))
                if let rate = Double(t.token?.exchange_rate ?? "") { usdTotal += amount * rate }
                let sym = t.token?.symbol ?? "?"
                let link = t.token?.address.map { "https://etherscan.io/token/\($0)?a=\(addr)" } ?? ""
                result.entities.append(.init(
                    kind: .document, label: "\(Self.fmt(amount)) \(sym)",
                    subtitle: "Token holding · \(t.token?.name ?? sym)",
                    confidence: 0.9, sourceURL: link, linkKind: .relatedTo, linkDirection: .fromInput))
            }
        }
        if usdTotal > 0 {
            result.inputAttributes.append(.init(key: "Est. value", value: BitcoinAddressPlugin.usd(usdTotal), source: "Blockscout"))
        }

        // First activity — single oldest-first query (no paging through blocks).
        if let furl = URL(string: "\(legacy)?module=account&action=txlist&address=\(addr.pathEncoded)&sort=asc&page=1&offset=1"),
           let first = try? await context.getJSON(Legacy.self, from: furl),
           let ts = first.result?.first?.timeStamp, let secs = Double(ts) {
            result.events.append(.init(title: "First Ethereum activity",
                                       date: Date(timeIntervalSince1970: secs), category: "On-chain", detail: addr))
        }

        // Last 25 transactions.
        if let xurl = URL(string: "\(base)/\(addr.pathEncoded)/transactions"),
           let txs = try? await context.getJSON(Txs.self, from: xurl), let items = txs.items, !items.isEmpty {
            if let latest = items.compactMap({ ISO8601Date.parse($0.timestamp) }).max() {
                result.events.append(.init(title: "Most recent Ethereum activity", date: latest, category: "On-chain", detail: addr))
            }
            for tx in items.prefix(25) {
                guard let hash = tx.hash else { continue }
                let outgoing = (tx.from?.hash?.lowercased() == addr.lowercased())
                let other = outgoing ? tx.to : tx.from
                let cp = other?.name ?? other?.ens_domain_name ?? CryptoAddress.short(other?.hash ?? "?")
                let arrow = outgoing ? "→" : "←"

                // Amount: native ETH if any, otherwise the first token transfer.
                var amountStr = ""
                let eth = (Double(tx.value ?? "") ?? 0) / 1e18
                if eth > 0 { amountStr = "\(Self.fmt(eth)) ETH" }
                else if let tt = tx.token_transfers?.first {
                    let dec = Int(tt.total?.decimals ?? tt.token?.decimals ?? "18") ?? 18
                    let v = (Double(tt.total?.value ?? "") ?? 0) / pow(10, Double(dec))
                    amountStr = "\(Self.fmt(v)) \(tt.token?.symbol ?? "tokens")"
                }
                let call = tx.decoded_input?.method_call ?? tx.method
                let head = amountStr.isEmpty ? (call ?? "transaction") : amountStr
                let label = "\(arrow) \(head) · \(cp)"

                var subtitleParts: [String] = []
                if other?.is_contract == true { subtitleParts.append("contract") }
                if let call, !call.isEmpty { subtitleParts.append(call) }
                subtitleParts.append("→ \(CryptoAddress.short(other?.hash ?? "?"))")

                result.entities.append(.init(
                    kind: .document, label: label,
                    subtitle: subtitleParts.joined(separator: " · "),
                    confidence: 0.85, sourceURL: txExplorer(hash),
                    linkKind: .mentions, linkDirection: .toInput))
            }
        }
        return result
    }

    private static func fmt(_ v: Double) -> String {
        if v == 0 { return "0" }
        var s = String(format: "%.6f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
