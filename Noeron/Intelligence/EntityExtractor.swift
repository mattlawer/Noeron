//
//  EntityExtractor.swift
//  Noeron
//
//  Detects selectors in free text so an analyst can paste a blob and have nodes
//  appear automatically. Powers the "type john@example.com → graph builds itself"
//  entry point.
//

import Foundation

struct ExtractedEntity: Hashable, Sendable {
    var kind: EntityKind
    var value: String
}

enum EntityExtractor {

    /// Extract all recognised selectors from a block of text, de-duplicated and ordered.
    static func extract(from text: String) -> [ExtractedEntity] {
        var found: [ExtractedEntity] = []
        var seen = Set<String>()
        func add(_ kind: EntityKind, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return }
            let key = "\(kind.rawValue)|\(v.lowercased())"
            if seen.insert(key).inserted { found.append(.init(kind: kind, value: v)) }
        }

        // Work on a mutable copy so matched spans can be blanked to avoid double counting.
        var working = text

        // 1. URLs (greedy first so their host isn't re-matched as a bare domain)
        for m in matches(Patterns.url, in: working) {
            add(.url, m)
        }
        working = blanking(Patterns.url, in: working)

        // 2. Emails
        for m in matches(Patterns.email, in: working) {
            add(.email, m.lowercased())
        }
        working = blanking(Patterns.email, in: working)

        // 3. Crypto wallets
        for m in matches(Patterns.eth, in: working) { add(.cryptoWallet, m) }
        for m in matches(Patterns.btc, in: working) where looksLikeBitcoin(m) { add(.cryptoWallet, m) }

        // 4. IPv4
        for m in matches(Patterns.ipv4, in: working) where validIPv4(m) { add(.ipAddress, m) }
        working = blanking(Patterns.ipv4, in: working)

        // 5. Domains (after URLs/emails/IPs removed)
        for m in matches(Patterns.domain, in: working) where isPlausibleDomain(m) {
            add(.domain, m.lowercased())
        }

        // 6. Phone numbers
        for m in matches(Patterns.phone, in: working) where validPhone(m) {
            add(.phone, normalizePhone(m))
        }

        // 7. @usernames
        for m in matches(Patterns.handle, in: working) {
            add(.username, m.hasPrefix("@") ? m : "@\(m)")
        }

        return found
    }

    /// Convenience: best single guess for a short single-token query.
    static func classifySingle(_ query: String) -> EntityKind {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = extract(from: q).first, first.value.caseInsensitiveCompare(q) == .orderedSame || extract(from: q).count == 1 {
            return first.kind
        }
        return q.contains(" ") ? .person : .domain
    }

    // MARK: Patterns

    private enum Patterns {
        static let url = #"https?://[^\s<>"')]+"#
        static let email = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        static let ipv4 = #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        static let domain = #"\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b"#
        static let eth = #"\b0x[a-fA-F0-9]{40}\b"#
        static let btc = #"\b(?:bc1[a-z0-9]{20,59}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})\b"#
        static let phone = #"\+?\d[\d\s().\-]{7,16}\d"#
        static let handle = #"(?<![\w.])@([A-Za-z0-9_]{2,30})\b"#
    }

    // MARK: Regex helpers

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { result in
            // Prefer capture group 1 when present (e.g. handle without '@').
            let groupRange = result.numberOfRanges > 1 && result.range(at: 1).location != NSNotFound
                ? result.range(at: 1) : result.range
            return Range(groupRange, in: text).map { String(text[$0]) }
        }
    }

    private static func blanking(_ pattern: String, in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    // MARK: Validation

    private static func validIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }
    }

    private static func isPlausibleDomain(_ s: String) -> Bool {
        let tld = s.split(separator: ".").last.map(String.init) ?? ""
        // Filter out obvious non-domains like version numbers caught by the regex.
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter } && !s.hasPrefix(".")
    }

    private static func looksLikeBitcoin(_ s: String) -> Bool {
        s.hasPrefix("bc1") || s.hasPrefix("1") || s.hasPrefix("3")
    }

    private static func validPhone(_ s: String) -> Bool {
        let digits = s.filter(\.isNumber)
        return digits.count >= 8 && digits.count <= 15
    }

    private static func normalizePhone(_ s: String) -> String {
        let digits = s.filter { $0.isNumber || $0 == "+" }
        return s.hasPrefix("+") ? "+\(digits.filter(\.isNumber))" : digits
    }
}
