//
//  TyposquatPlugin.swift
//  Noeron
//
//  dnstwist-style look-alike domain generation (omission, transposition,
//  replacement, homoglyph, TLD swap) — reports the ones that actually resolve,
//  i.e. candidate phishing / impersonation domains. Keyless.
//

import Foundation

struct TyposquatPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "typosquat",
            name: "Typosquat / Look-alikes",
            summary: "Generates dnstwist-style look-alike domains (omission, transposition, replacement, homoglyph, TLD swap) and reports the ones that actually resolve — candidate phishing / impersonation domains. Keyless.",
            category: .threat,
            acceptedKinds: [.domain],
            producesKinds: [.domain],
            requiresAPIKey: false,
            docURL: "https://github.com/elceef/dnstwist",
            isLive: true,
            symbol: "exclamationmark.triangle.fill"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { throw PluginError.unsupportedEntity }
        let name = parts[0]
        let suffix = parts.dropFirst().joined(separator: ".")
        guard name.count >= 3 else { throw PluginError.unsupportedEntity }

        let candidates = Array(Self.permutations(name: name, suffix: suffix, originalTLD: suffix)).sorted().prefix(50)
        let ctx = context

        // Bounded-concurrency resolution check.
        let live: [String] = await withTaskGroup(of: String?.self) { group in
            var it = candidates.makeIterator()
            var inFlight = 0
            func addNext() {
                guard let cand = it.next() else { return }
                group.addTask { await DNSoverHTTPS.resolves(cand, context: ctx) ? cand : nil }
                inFlight += 1
            }
            for _ in 0..<10 { addNext() }
            var found: [String] = []
            while inFlight > 0, let outcome = await group.next() {
                inFlight -= 1
                if let c = outcome { found.append(c) }
                addNext()
            }
            return found
        }

        var result = PluginResult(rawExcerpt: "Typosquat: \(live.count) of \(candidates.count) look-alikes resolve")
        result.inputAttributes.append(.init(key: "Live look-alikes", value: "\(live.count) of \(candidates.count) checked", source: "Typosquat"))
        for cand in live.sorted() {
            result.entities.append(.init(
                kind: .domain, label: cand, subtitle: "Resolving look-alike (possible typosquat)",
                confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        return result
    }

    // QWERTY adjacency for plausible fat-finger replacements.
    private static let adjacency: [Character: [Character]] = [
        "a": ["q","s","z"], "b": ["v","g","n"], "c": ["x","d","v"], "d": ["s","f","e"],
        "e": ["w","r","d"], "g": ["f","h","t"], "i": ["u","o","k"], "l": ["k","o","p"],
        "m": ["n","j","k"], "n": ["b","m","h"], "o": ["i","p","l"], "p": ["o","l"],
        "r": ["e","t","f"], "s": ["a","d","w"], "t": ["r","y","g"], "u": ["y","i","j"],
        "v": ["c","b","g"], "w": ["q","e","s"], "y": ["t","u","h"]
    ]
    private static let homoglyph: [Character: Character] = ["o": "0", "l": "1", "i": "1", "e": "3", "a": "4", "s": "5"]

    static func permutations(name: String, suffix: String, originalTLD: String) -> Set<String> {
        let chars = Array(name)
        var names = Set<String>()
        // Omission
        for i in chars.indices { var c = chars; c.remove(at: i); names.insert(String(c)) }
        // Repetition
        for i in chars.indices { var c = chars; c.insert(chars[i], at: i); names.insert(String(c)) }
        // Transposition
        if chars.count > 1 { for i in 0..<(chars.count - 1) { var c = chars; c.swapAt(i, i + 1); names.insert(String(c)) } }
        // Replacement (keyboard-adjacent)
        for i in chars.indices { for r in adjacency[chars[i]] ?? [] { var c = chars; c[i] = r; names.insert(String(c)) } }
        // Homoglyph
        for i in chars.indices where homoglyph[chars[i]] != nil { var c = chars; c[i] = homoglyph[chars[i]]!; names.insert(String(c)) }
        // Hyphenation
        if chars.count > 2 { for i in 1..<chars.count { var c = chars; c.insert("-", at: i); names.insert(String(c)) } }
        names.remove(name)

        var domains = Set(names.map { "\($0).\(suffix)" })
        // TLD swaps on the genuine name.
        for tld in ["com", "net", "org", "co", "io", "info", "app", "xyz", "online", "site"] where tld != originalTLD {
            domains.insert("\(name).\(tld)")
        }
        return domains
    }
}
