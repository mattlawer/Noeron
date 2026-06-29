//
//  WhoisPlugin.swift
//  Noeron
//
//  Live WHOIS over TCP port 43 with IANA referral chaining. No API key.
//  domain → registrar / registrant org & person / name servers / lifecycle dates.
//

import Foundation
import Network

// MARK: - Raw WHOIS client (port 43)

enum WhoisClient {
    /// Send `query\r\n` to `server:43` and collect the full text response.
    static func query(_ query: String, server: String, port: UInt16 = 43, timeout: TimeInterval = 12) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(server),
                port: NWEndpoint.Port(rawValue: port) ?? 43,
                using: .tcp
            )
            let box = ResultBox(continuation: continuation, connection: connection)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let payload = (query + "\r\n").data(using: .utf8) ?? Data()
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error { box.fail(.network(error.localizedDescription)) }
                        else { box.receiveLoop() }
                    })
                case .failed(let error):
                    box.fail(.network(error.localizedDescription))
                case .cancelled:
                    box.finishWithAccumulated()
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                box.timeout()
            }
        }
    }

    /// Coordinates the receive loop and single-shot continuation resume.
    private final class ResultBox: @unchecked Sendable {
        private let continuation: CheckedContinuation<String, Error>
        private let connection: NWConnection
        private var buffer = Data()
        private var finished = false
        private let lock = NSLock()

        init(continuation: CheckedContinuation<String, Error>, connection: NWConnection) {
            self.continuation = continuation
            self.connection = connection
        }

        func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty { self.lock.withLock { self.buffer.append(data) } }
                if let error { self.fail(.network(error.localizedDescription)); return }
                if isComplete { self.finishWithAccumulated(); return }
                self.receiveLoop()
            }
        }

        func finishWithAccumulated() {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            let text = String(decoding: buffer, as: UTF8.self)
            connection.cancel()
            continuation.resume(returning: text)
        }

        func fail(_ error: PluginError) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            continuation.resume(throwing: error)
        }

        func timeout() {
            lock.lock()
            let alreadyDone = finished
            let hasData = !buffer.isEmpty
            lock.unlock()
            if alreadyDone { return }
            if hasData { finishWithAccumulated() } else { fail(.network("WHOIS timed out")) }
        }
    }
}

// MARK: - Plugin

struct WhoisPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "whois",
            name: "WHOIS",
            summary: "Registrar, registrant and lifecycle dates for a domain via port-43 WHOIS.",
            category: .network,
            acceptedKinds: [.domain],
            producesKinds: [.company, .person, .domain],
            isLive: true,
            symbol: "doc.text.magnifyingglass"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)
        guard let tld = domain.split(separator: ".").last.map(String.init), !tld.isEmpty else {
            throw PluginError.unsupportedEntity
        }

        // 1. Ask IANA which WHOIS server is authoritative for this TLD.
        var server = "whois.iana.org"
        if let referral = try? await WhoisClient.query(tld, server: "whois.iana.org"),
           let refServer = WhoisPlugin.field(in: referral, keys: ["refer", "whois"]) {
            server = refServer
        }

        // 2. Query that server for the domain.
        let raw = try await WhoisClient.query(domain, server: server)
        var result = PluginResult(rawExcerpt: raw.truncatedExcerpt())

        // Lifecycle dates → timeline
        if let created = WhoisPlugin.date(in: raw, keys: ["Creation Date", "Created On", "created", "Registered on", "Registration Time"]) {
            result.events.append(.init(title: "Domain registered: \(domain)", date: created, category: "Domain", detail: "WHOIS creation date"))
            result.inputAttributes.append(.init(key: "Created", value: WhoisPlugin.iso(created), kind: .date, source: "WHOIS"))
        }
        if let expiry = WhoisPlugin.date(in: raw, keys: ["Registry Expiry Date", "Expiration Date", "Expiry date", "paid-till", "Registrar Registration Expiration Date"]) {
            result.events.append(.init(title: "Domain expires: \(domain)", date: expiry, category: "Domain", detail: "WHOIS expiry date"))
            result.inputAttributes.append(.init(key: "Expires", value: WhoisPlugin.iso(expiry), kind: .date, source: "WHOIS"))
        }
        if let updated = WhoisPlugin.date(in: raw, keys: ["Updated Date", "last-update", "Last Modified"]) {
            result.events.append(.init(title: "WHOIS record updated: \(domain)", date: updated, category: "Domain", detail: "WHOIS last update"))
        }

        // Registrar / status / name servers → input attributes
        if let registrar = WhoisPlugin.field(in: raw, keys: ["Registrar", "Sponsoring Registrar"]) {
            result.inputAttributes.append(.init(key: "Registrar", value: registrar, source: "WHOIS"))
        }
        let statuses = WhoisPlugin.fields(in: raw, keys: ["Domain Status", "status"])
        if !statuses.isEmpty {
            result.inputAttributes.append(.init(key: "Status", value: statuses.prefix(3).joined(separator: ", "), source: "WHOIS"))
        }

        // Registrant org → Company node
        if let org = WhoisPlugin.field(in: raw, keys: ["Registrant Organization", "Registrant Org", "org", "OrgName"]),
           !WhoisPlugin.isRedacted(org) {
            result.entities.append(.init(
                kind: .company, label: org, subtitle: "Registrant organization",
                confidence: 0.8, attributes: [.init(key: "Role", value: "Domain registrant", source: "WHOIS")],
                linkKind: .registeredBy, linkDirection: .fromInput
            ))
        }

        // Registrant person → Person node
        if let name = WhoisPlugin.field(in: raw, keys: ["Registrant Name", "Registrant"]),
           !WhoisPlugin.isRedacted(name) {
            result.entities.append(.init(
                kind: .person, label: name, subtitle: "Registrant contact",
                confidence: 0.6, linkKind: .registeredBy, linkDirection: .fromInput
            ))
        }

        // Name servers → related domains (skip managed-DNS provider infrastructure).
        for ns in WhoisPlugin.fields(in: raw, keys: ["Name Server", "nserver"]).prefix(6) {
            let host = ns.lowercased()
            guard !InfraFilter.isInfrastructure(host) else { continue }
            result.entities.append(.init(
                kind: .domain, label: host, subtitle: "Name server",
                confidence: 0.5, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        return result
    }

    // MARK: Parsing helpers

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) } // email→domain
        return s
    }

    static func isRedacted(_ value: String) -> Bool {
        let v = value.lowercased()
        return ["redacted", "privacy", "data protected", "withheld", "gdpr", "not disclosed", "whoisguard", "perfect privacy"]
            .contains { v.contains($0) }
    }

    /// First value for any of the given keys (case-insensitive, `key: value`).
    static func field(in text: String, keys: [String]) -> String? {
        fields(in: text, keys: keys).first
    }

    static func fields(in text: String, keys: [String]) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            if keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { out.append(value) }
            }
        }
        return out
    }

    static func date(in text: String, keys: [String]) -> Date? {
        guard let raw = field(in: text, keys: keys) else { return nil }
        let candidates = [
            "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd", "yyyy.MM.dd", "dd-MMM-yyyy"
        ]
        let trimmed = String(raw.prefix(40))
        for fmt in candidates {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) { return d }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    static func iso(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
