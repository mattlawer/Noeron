//
//  SolanaAddressPlugin.swift
//  Noeron
//
//  Keyless Solana on-chain intel via the public mainnet JSON-RPC. Lists the
//  account: SOL balance + USD estimate, SPL token holdings (each openable in the
//  explorer), recent activity window, and the last 25 transaction signatures
//  (time, status, explorer link). Emits `.document` nodes only — no related-wallet
//  fan-out. Best-effort: the public RPC rate-limits, so failures degrade gracefully.
//

import Foundation

struct SolanaAddressPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "sol-onchain",
            name: "Solana On-chain",
            summary: "SOL balance + USD, SPL token holdings and the last 25 transactions (with explorer links) for a Solana address (public RPC). Keyless.",
            category: .blockchain,
            acceptedKinds: [.cryptoWallet],
            producesKinds: [.document],
            requiresAPIKey: false,
            parameterFields: [.init(key: "sol.rpcURL", label: "RPC endpoint",
                                    hint: "A dedicated RPC (Helius, QuickNode…) avoids the public rate limits.",
                                    placeholder: "https://api.mainnet-beta.solana.com")],
            docURL: "https://solana.com/docs/rpc",
            isLive: true,
            symbol: "circle.hexagongrid.fill"
        )
    }

    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool {
        entity.kind == .cryptoWallet && CryptoAddress.chain(of: entity.label) == .solana
    }

    private static let defaultHost = "https://api.mainnet-beta.solana.com"

    private struct RPC<T: Decodable>: Decodable { let result: T? }
    private struct BalanceResult: Decodable { let value: Int? }
    private struct AnyErr: Decodable {}
    private struct Sig: Decodable { let signature: String?; let blockTime: Double?; let err: AnyErr? }
    private struct TokenAccounts: Decodable {
        let value: [Acct]?
        struct Acct: Decodable {
            let account: Account?
            struct Account: Decodable { let data: DataObj?
                struct DataObj: Decodable { let parsed: Parsed?
                    struct Parsed: Decodable { let info: Info?
                        struct Info: Decodable { let mint: String?; let tokenAmount: Amount?
                            struct Amount: Decodable { let uiAmountString: String? } } } } }
        }
    }

    private func rpc(_ method: String, _ params: [Any], _ context: PluginContext) async -> Data? {
        let host = context.parameter("sol.rpcURL") ?? Self.defaultHost
        guard let url = URL(string: host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Noeron/1.0 (OSINT workspace)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        guard let (data, resp) = try? await context.session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func sol(_ lamports: Int) -> String { String(format: "%.4f", Double(lamports) / 1e9) }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let addr = entity.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CryptoAddress.chain(of: addr) == .solana else { throw PluginError.unsupportedEntity }

        var result = PluginResult()
        result.inputAttributes.append(.init(key: "Chain", value: "Solana", source: "Solana RPC"))
        result.inputAttributes.append(.init(key: "Explorer", value: "https://solscan.io/account/\(addr)", kind: .url, source: "Solana RPC"))

        // Balance (+ USD estimate)
        if let data = await rpc("getBalance", [addr], context),
           let r = try? JSONDecoder().decode(RPC<BalanceResult>.self, from: data), let lamports = r.result?.value {
            let sol = Double(lamports) / 1e9
            result.inputAttributes.append(.init(key: "Balance", value: "\(Self.sol(lamports)) SOL", source: "Solana RPC"))
            if sol > 0,
               let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd"),
               let price = try? await context.getJSON([String: [String: Double]].self, from: url),
               let usd = price["solana"]?["usd"] {
                result.inputAttributes.append(.init(key: "Est. value", value: BitcoinAddressPlugin.usd(sol * usd), source: "CoinGecko"))
            }
        } else {
            return PluginResult(rawExcerpt: "Solana: no RPC response (public endpoint may be rate-limited)")
        }

        // SPL token holdings → count + one openable node per token.
        if let data = await rpc("getTokenAccountsByOwner",
                                [addr, ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"], ["encoding": "jsonParsed"]],
                                context),
           let r = try? JSONDecoder().decode(RPC<TokenAccounts>.self, from: data) {
            let held = (r.result?.value ?? []).compactMap { a -> (mint: String, amount: String)? in
                guard let info = a.account?.data?.parsed?.info, let mint = info.mint,
                      let amt = info.tokenAmount?.uiAmountString, (Double(amt) ?? 0) > 0 else { return nil }
                return (mint, amt)
            }
            if !held.isEmpty {
                result.inputAttributes.append(.init(key: "Tokens found", value: String(held.count), kind: .number, source: "Solana RPC"))
                for t in held.prefix(25) {
                    result.entities.append(.init(
                        kind: .document, label: "\(t.amount) \(CryptoAddress.short(t.mint))",
                        subtitle: "SPL token holding",
                        confidence: 0.9, sourceURL: "https://solscan.io/token/\(t.mint)",
                        linkKind: .relatedTo, linkDirection: .fromInput))
                }
            }
        }

        // Last 25 transaction signatures → activity window + one node each.
        if let data = await rpc("getSignaturesForAddress", [addr, ["limit": 25]], context),
           let r = try? JSONDecoder().decode(RPC<[Sig]>.self, from: data), let sigs = r.result, !sigs.isEmpty {
            result.inputAttributes.append(.init(key: "Recent transactions", value: String(sigs.count), kind: .number, source: "Solana RPC"))
            let times = sigs.compactMap { $0.blockTime }
            if let oldest = times.min() {
                result.events.append(.init(title: "Solana activity (oldest in recent window)",
                                           date: Date(timeIntervalSince1970: oldest), category: "On-chain", detail: addr))
            }
            if let latest = times.max() {
                result.events.append(.init(title: "Most recent Solana activity",
                                           date: Date(timeIntervalSince1970: latest), category: "On-chain", detail: addr))
            }
            let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
            for sig in sigs.prefix(25) {
                guard let s = sig.signature else { continue }
                var subtitle = sig.err == nil ? "success" : "failed"
                if let t = sig.blockTime { subtitle = "\(dateFmt.string(from: Date(timeIntervalSince1970: t))) · \(subtitle)" }
                result.entities.append(.init(
                    kind: .document, label: "tx \(CryptoAddress.short(s))", subtitle: subtitle,
                    confidence: 0.85, sourceURL: "https://solscan.io/tx/\(s)",
                    linkKind: .mentions, linkDirection: .toInput))
            }
        }

        result.rawExcerpt = "Solana on-chain for \(addr)"
        return result
    }
}
