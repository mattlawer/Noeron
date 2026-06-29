//
//  EmailIntel.swift
//  Noeron
//
//  Shared keyless email helpers used by the email plugins (and a few others):
//  parsing, Gmail/MD5 helpers, disposable/role lists, and MX-based mail-host
//  classification.
//

import Foundation
import CryptoKit

enum EmailIntel {
    /// Split "john.doe+tag@Example.COM" → (local: "john.doe+tag", domain: "example.com").
    static func parts(of raw: String) -> (local: String, domain: String)? {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = e.lastIndex(of: "@") else { return nil }
        let local = String(e[..<at])
        let domain = String(e[e.index(after: at)...])
        guard !local.isEmpty, domain.contains(".") else { return nil }
        return (local, domain)
    }

    /// Local part with any "+tag" sub-address removed (e.g. "john+news" → "john").
    static func baseLocal(_ local: String) -> String {
        local.split(separator: "+", maxSplits: 1).first.map(String.init) ?? local
    }

    static func md5Hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Disposable / throwaway providers (subset of the well-known offenders).
    static let disposableProviders: Set<String> = [
        "mailinator.com", "guerrillamail.com", "guerrillamail.info", "10minutemail.com",
        "tempmail.com", "temp-mail.org", "throwawaymail.com", "yopmail.com", "getnada.com",
        "trashmail.com", "sharklasers.com", "maildrop.cc", "dispostable.com", "fakeinbox.com",
        "mailnesia.com", "mintemail.com", "mohmal.com", "spamgourmet.com", "mytemp.email",
        "moakt.com", "emailondeck.com", "tempmailo.com", "1secmail.com", "burnermail.io",
        "discard.email", "33mail.com", "spam4.me", "tempr.email", "inboxbear.com"
    ]

    /// Local parts that indicate a shared role mailbox rather than a person.
    static let roleAccounts: Set<String> = [
        "info", "admin", "administrator", "support", "help", "helpdesk", "sales",
        "contact", "hello", "hi", "office", "billing", "accounts", "accounting",
        "hr", "jobs", "careers", "recruitment", "press", "media", "marketing",
        "noreply", "no-reply", "donotreply", "postmaster", "webmaster", "abuse",
        "security", "privacy", "legal", "team", "service", "enquiries", "mail"
    ]

    /// Classify the mail provider from its MX hostnames.
    static func mailHost(forMX hosts: [String]) -> String? {
        let joined = hosts.joined(separator: " ").lowercased()
        let signatures: [(String, [String])] = [
            ("Google Workspace / Gmail", ["google.com", "googlemail.com", "aspmx.l.google"]),
            ("Microsoft 365 / Outlook", ["protection.outlook.com", "outlook.com", "office365"]),
            ("Proton Mail", ["protonmail.ch", "proton.me", "protonmail"]),
            ("Apple iCloud", ["icloud.com", "apple.com", "mail.me.com"]),
            ("Yahoo", ["yahoodns.net", "yahoo.com"]),
            ("Zoho", ["zoho.com", "zohomail", "zoho.eu"]),
            ("Yandex", ["yandex", "mx.yandex"]),
            ("Fastmail", ["messagingengine.com", "fastmail"]),
            ("GMX / 1&1 IONOS", ["gmx.net", "kundenserver.de", "1and1", "ionos"]),
            ("Amazon WorkMail / SES", ["awsapps.com", "amazonaws.com"]),
            ("Mimecast (gateway)", ["mimecast"]),
            ("Proofpoint (gateway)", ["pphosted.com", "proofpoint"]),
            ("Barracuda (gateway)", ["barracudanetworks", "cudaops"])
        ]
        for (label, needles) in signatures where needles.contains(where: { joined.contains($0) }) {
            return label
        }
        return nil
    }
}
