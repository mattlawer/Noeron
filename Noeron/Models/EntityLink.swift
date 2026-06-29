//
//  EntityLink.swift
//  Noeron
//
//  A directed, typed edge between two entities. Named `EntityLink` (not
//  "Relationship") to avoid colliding with SwiftData's `@Relationship` macro.
//

import Foundation
import SwiftData

/// Semantic edge labels surfaced by plugins and the discovery engine.
enum LinkKind: String, Codable, CaseIterable, Sendable {
    case resolvesTo          // domain -> ip
    case hostedOn            // domain -> ip / asn
    case registeredBy        // domain -> person/company (WHOIS)
    case ownedBy             // company -> person
    case employs             // company -> person
    case memberOf            // person -> company
    case hasEmail            // person -> email
    case hasPhone            // person -> phone
    case hasUsername         // person/email -> username
    case hasProfile          // person -> socialProfile
    case controls            // person -> cryptoWallet / domain
    case issuedFor           // certificate -> domain
    case subdomainOf         // subdomain -> domain
    case partOf              // ip -> asn
    case appearsIn           // email -> breach
    case mentions            // note/document -> any
    case relatedTo           // generic

    var displayName: String {
        switch self {
        case .resolvesTo: "resolves to"
        case .hostedOn: "hosted on"
        case .registeredBy: "registered by"
        case .ownedBy: "owned by"
        case .employs: "employs"
        case .memberOf: "member of"
        case .hasEmail: "has email"
        case .hasPhone: "has phone"
        case .hasUsername: "has username"
        case .hasProfile: "has profile"
        case .controls: "controls"
        case .issuedFor: "issued for"
        case .subdomainOf: "subdomain of"
        case .partOf: "part of"
        case .appearsIn: "appears in"
        case .mentions: "mentions"
        case .relatedTo: "related to"
        }
    }
}

@Model
final class EntityLink {
    var id: UUID = UUID()
    var kindRaw: String = LinkKind.relatedTo.rawValue
    /// Optional custom label overriding the kind's default text.
    var customLabel: String = ""
    var confidence: Double = 1.0
    var createdAt: Date = Date()
    var sourcePlugin: String = ""
    var directed: Bool = true

    var source: Entity?
    var target: Entity?
    var investigation: Investigation?

    init(kind: LinkKind,
         source: Entity?,
         target: Entity?,
         confidence: Double = 1.0,
         sourcePlugin: String = "",
         directed: Bool = true) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.source = source
        self.target = target
        self.confidence = confidence
        self.sourcePlugin = sourcePlugin
        self.directed = directed
        self.createdAt = Date()
    }
}

extension EntityLink {
    var kind: LinkKind {
        get { LinkKind(rawValue: kindRaw) ?? .relatedTo }
        set { kindRaw = newValue.rawValue }
    }
    var label: String { customLabel.isEmpty ? kind.displayName : customLabel }

    /// Undirected identity for de-duplicating edges.
    var dedupeKey: String {
        let a = source?.id.uuidString ?? "?"
        let b = target?.id.uuidString ?? "?"
        return "\(kindRaw)|\(a)->\(b)"
    }
}
