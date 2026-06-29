//
//  Normalizer.swift
//  Noeron
//
//  Canonicalises labels per kind so the discovery engine de-duplicates reliably
//  (e.g. "Example.com", "example.com." and "WWW.example.com" collapse to one node).
//

import Foundation

enum Normalizer {
    static func label(for kind: EntityKind, _ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .domain, .subdomain:
            var s = trimmed.lowercased().trimmingTrailingDot()
            if s.hasPrefix("www.") { s.removeFirst(4) }
            return s
        case .email, .url:
            return trimmed.lowercased()
        case .ipAddress:
            return trimmed
        case .asn:
            return trimmed.uppercased()
        case .cryptoWallet:
            return trimmed.hasPrefix("0x") ? trimmed.lowercased() : trimmed
        case .username:
            // Collapse "@handle" and "handle" to one node so plugins don't run twice
            // and emit duplicate findings/events for the same account.
            var s = trimmed
            while s.hasPrefix("@") { s.removeFirst() }
            return s
        default:
            return trimmed
        }
    }
}
