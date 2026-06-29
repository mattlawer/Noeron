//
//  CryptoAddress.swift
//  Noeron
//
//  Lightweight crypto-address classification shared by the on-chain plugins, so
//  each plugin only runs on the chain it understands.
//

import Foundation

enum CryptoAddress {
    enum Chain { case bitcoin, ethereum, solana }

    /// Base58 alphabet (Bitcoin/Solana) — excludes 0, O, I, l.
    private static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func chain(of raw: String) -> Chain? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ethereum (and EVM): 0x + 40 hex chars.
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            let hex = s.dropFirst(2)
            if hex.count == 40, hex.allSatisfy({ $0.isHexDigit }) { return .ethereum }
            return nil
        }
        // Bitcoin: bech32 (bc1…) or base58 (1…/3…).
        let lower = s.lowercased()
        if lower.hasPrefix("bc1"), s.count >= 14, s.count <= 90 { return .bitcoin }
        if (s.hasPrefix("1") || s.hasPrefix("3")), s.count >= 26, s.count <= 35 { return .bitcoin }
        // Solana: base58, 32–44 chars, no bc1/1/3 Bitcoin prefix collision handled above.
        if s.count >= 32, s.count <= 44, s.allSatisfy({ base58.contains($0) }) { return .solana }
        return nil
    }

    /// "0x1234…cdef" — a compact display form for long addresses/hashes.
    static func short(_ s: String) -> String {
        s.count > 14 ? "\(s.prefix(8))…\(s.suffix(4))" : s
    }
}
