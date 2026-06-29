//
//  BitcoinAddressPlugin.swift
//  Noeron
//
//  Keyless Bitcoin on-chain intel via Blockstream's Esplora API: balance, totals,
//  a USD estimate, first/last activity (one Blockchair call — no block looping) and
//  the last 25 transactions (net amount, counterparty, explorer link). It lists the
//  address rather than fanning out into related wallets, so the graph stays readable.
//

import Foundation

struct BitcoinAddressPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "btc-onchain",
            name: "Bitcoin On-chain",
            summary: "Balance, USD estimate, first/last activity and the last 25 transactions (amount, counterparty, explorer link) for a Bitcoin address (Blockstream Esplora). Keyless.",
            category: .blockchain,
            acceptedKinds: [.cryptoWallet],
            producesKinds: [.document],
            requiresAPIKey: false,
            parameterFields: [.init(key: "btc.esploraBase", label: "Esplora API base",
                                    hint: "Any Esplora-compatible endpoint (e.g. a self-hosted instance or mempool.space/api).",
                                    placeholder: "https://blockstream.info/api")],
            docURL: "https://github.com/Blockstream/esplora/blob/master/API.md",
            isLive: true,
            symbol: "bitcoinsign.circle.fill"
        )
    }

    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool {
        entity.kind == .cryptoWallet && CryptoAddress.chain(of: entity.label) == .bitcoin
    }

    private struct AddrInfo: Decodable {
        let chain_stats: Stats?
        struct Stats: Decodable { let funded_txo_sum: Int?; let spent_txo_sum: Int?; let tx_count: Int? }
    }
    private struct Tx: Decodable {
        let txid: String?
        let status: Status?
        let vin: [Vin]?
        let vout: [Vout]?
        struct Status: Decodable { let block_time: Double? }
        struct Vin: Decodable { let prevout: Prevout?; struct Prevout: Decodable { let scriptpubkey_address: String?; let value: Int? } }
        struct Vout: Decodable { let scriptpubkey_address: String?; let value: Int? }
    }
    private struct Ticker: Decodable { let last: Double? }
    private struct Blockchair: Decodable {
        let data: [String: Entry]?
        struct Entry: Decodable { let address: Addr?
            struct Addr: Decodable { let first_seen_receiving: String?; let last_seen_spending: String?; let last_seen_receiving: String? } }
    }

    private static func btc(_ sats: Int) -> String { String(format: "%.8f", Double(sats) / 1e8) }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let addr = entity.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let esplora = context.parameter("btc.esploraBase") ?? "https://blockstream.info/api"
        guard CryptoAddress.chain(of: addr) == .bitcoin,
              let infoURL = URL(string: "\(esplora)/address/\(addr.pathEncoded)") else {
            throw PluginError.unsupportedEntity
        }

        let (data, http) = try await context.get(infoURL)
        guard http.statusCode == 200, let info = try? JSONDecoder().decode(AddrInfo.self, from: data),
              let s = info.chain_stats else {
            return PluginResult(rawExcerpt: "Bitcoin: address not found / HTTP \(http.statusCode)")
        }

        let funded = s.funded_txo_sum ?? 0, spent = s.spent_txo_sum ?? 0
        let balanceBTC = Double(funded - spent) / 1e8
        var result = PluginResult(rawExcerpt: "BTC \(Self.btc(funded - spent)) balance, \(s.tx_count ?? 0) txs")
        result.inputAttributes.append(.init(key: "Chain", value: "Bitcoin", source: "Blockstream"))
        result.inputAttributes.append(.init(key: "Balance", value: "\(Self.btc(funded - spent)) BTC", source: "Blockstream"))
        result.inputAttributes.append(.init(key: "Total received", value: "\(Self.btc(funded)) BTC", source: "Blockstream"))
        result.inputAttributes.append(.init(key: "Total sent", value: "\(Self.btc(spent)) BTC", source: "Blockstream"))
        result.inputAttributes.append(.init(key: "Transactions", value: String(s.tx_count ?? 0), kind: .number, source: "Blockstream"))
        result.inputAttributes.append(.init(key: "Explorer", value: "https://mempool.space/address/\(addr)", kind: .url, source: "Blockstream"))

        // USD estimate (single call to the public price ticker).
        if balanceBTC > 0,
           let url = URL(string: "https://blockchain.info/ticker"),
           let tickers = try? await context.getJSON([String: Ticker].self, from: url),
           let usd = tickers["USD"]?.last {
            result.inputAttributes.append(.init(key: "Est. value", value: BitcoinAddressPlugin.usd(balanceBTC * usd), source: "blockchain.info"))
        }

        // First / last activity via one Blockchair dashboard call (no block looping).
        if let url = URL(string: "https://api.blockchair.com/bitcoin/dashboards/address/\(addr.pathEncoded)?limit=0"),
           let bc = try? await context.getJSON(Blockchair.self, from: url),
           let a = bc.data?[addr]?.address {
            if let d = ISO8601Date.parse(a.first_seen_receiving) {
                result.events.append(.init(title: "First Bitcoin activity", date: d, category: "On-chain", detail: addr))
            }
            if let d = ISO8601Date.parse(a.last_seen_spending) ?? ISO8601Date.parse(a.last_seen_receiving) {
                result.events.append(.init(title: "Most recent Bitcoin activity", date: d, category: "On-chain", detail: addr))
            }
        }

        // Last 25 transactions (Esplora returns newest-first, ~25).
        if let txURL = URL(string: "\(esplora)/address/\(addr.pathEncoded)/txs"),
           let txs = try? await context.getJSON([Tx].self, from: txURL), !txs.isEmpty {
            if !result.events.contains(where: { $0.title.hasPrefix("Most recent") }),
               let latest = txs.compactMap({ $0.status?.block_time }).max() {
                result.events.append(.init(title: "Most recent Bitcoin activity",
                                           date: Date(timeIntervalSince1970: latest), category: "On-chain", detail: addr))
            }
            for tx in txs.prefix(25) {
                guard let txid = tx.txid else { continue }
                let received = (tx.vout ?? []).filter { $0.scriptpubkey_address == addr }.compactMap { $0.value }.reduce(0, +)
                let sent = (tx.vin ?? []).compactMap { $0.prevout }.filter { $0.scriptpubkey_address == addr }.compactMap { $0.value }.reduce(0, +)
                let net = received - sent
                let outgoing = net < 0
                let cp = outgoing
                    ? (tx.vout ?? []).compactMap { $0.scriptpubkey_address }.first { $0 != addr }
                    : (tx.vin ?? []).compactMap { $0.prevout?.scriptpubkey_address }.first { $0 != addr }
                let arrow = outgoing ? "→" : "←"
                let label = "\(arrow) \(Self.btc(abs(net))) BTC · \(CryptoAddress.short(cp ?? "?"))"
                var subtitle = "Transaction"
                if let t = tx.status?.block_time {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    subtitle = f.string(from: Date(timeIntervalSince1970: t))
                }
                result.entities.append(.init(
                    kind: .document, label: label, subtitle: subtitle,
                    confidence: 0.85, sourceURL: "https://mempool.space/tx/\(txid)",
                    linkKind: .mentions, linkDirection: .toInput))
            }
        }
        return result
    }

    static func usd(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
