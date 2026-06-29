//
//  Entity.swift
//  Noeron
//
//  A unified graph node. Rather than 13 polymorphic classes, every node is an
//  `Entity` tagged with an `EntityKind`. Kind-specific fields live in a typed,
//  JSON-encoded attribute bag so the schema stays flat and CloudKit-friendly.
//

import Foundation
import SwiftData

/// One typed key/value fact attached to an entity (e.g. registrar = "GoDaddy").
struct EntityAttribute: Codable, Hashable, Sendable, Identifiable {
    enum ValueKind: String, Codable, Sendable {
        case text, number, date, url, boolean
    }
    var id: UUID = UUID()
    var key: String
    var value: String
    var kind: ValueKind = .text
    /// Plugin that contributed this fact (provenance for court-ready reports).
    var source: String = ""
}

@Model
final class Entity {
    var id: UUID = UUID()

    /// Backing store for `EntityKind`; SwiftData persists the raw string.
    var kindRaw: String = EntityKind.person.rawValue

    /// Primary display value, e.g. "john@example.com" or "ACME Ltd".
    var label: String = ""
    /// Secondary line, e.g. a role, country, or normalised form.
    var subtitle: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// 0…1 analyst/plugin confidence used for graph styling and report flags.
    var confidence: Double = 1.0
    var pinned: Bool = false
    var isSeed: Bool = false

    /// Persisted graph-canvas position so layouts survive sync.
    var canvasX: Double = 0
    var canvasY: Double = 0

    /// Provenance for the node itself.
    var sourcePlugin: String = ""
    var sourceURLString: String = ""

    /// JSON-encoded `[EntityAttribute]`.
    var attributesData: Data = Data()

    // Relationships
    var investigation: Investigation?

    @Relationship(deleteRule: .cascade, inverse: \EntityLink.source)
    var outgoingLinks: [EntityLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \EntityLink.target)
    var incomingLinks: [EntityLink]? = []

    /// Set for `.image` / `.document` kinds (one-to-one with the evidence file).
    @Relationship(deleteRule: .nullify, inverse: \EvidenceItem.sourceEntity)
    var evidence: EvidenceItem?

    /// Inverses for notes / timeline events that annotate this entity. Declaring
    /// them here (rather than only on the child) satisfies CloudKit's requirement
    /// that every relationship has an inverse.
    @Relationship(deleteRule: .nullify, inverse: \NoteItem.entity)
    var notes: [NoteItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \TimelineEvent.entity)
    var events: [TimelineEvent]? = []

    init(kind: EntityKind,
         label: String,
         subtitle: String = "",
         confidence: Double = 1.0,
         isSeed: Bool = false,
         sourcePlugin: String = "",
         sourceURL: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.label = label
        self.subtitle = subtitle
        self.confidence = confidence
        self.isSeed = isSeed
        self.sourcePlugin = sourcePlugin
        self.sourceURLString = sourceURL
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Typed accessors

extension Entity {
    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var attributes: [EntityAttribute] {
        get { (try? JSONDecoder().decode([EntityAttribute].self, from: attributesData)) ?? [] }
        set { attributesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var outgoing: [EntityLink] { outgoingLinks ?? [] }
    var incoming: [EntityLink] { incomingLinks ?? [] }

    /// Distinct neighbours regardless of edge direction.
    var neighbors: [Entity] {
        var seen = Set<UUID>()
        var result: [Entity] = []
        for link in outgoing { if let t = link.target, seen.insert(t.id).inserted { result.append(t) } }
        for link in incoming { if let s = link.source, seen.insert(s.id).inserted { result.append(s) } }
        return result
    }

    var degree: Int { outgoing.count + incoming.count }

    func attribute(_ key: String) -> String? {
        attributes.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// Merge in a fact, overwriting an existing key only when the new value is non-empty.
    func setAttribute(_ key: String, _ value: String, kind: EntityAttribute.ValueKind = .text, source: String = "") {
        guard !value.isEmpty else { return }
        var bag = attributes
        if let idx = bag.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            bag[idx].value = value
            bag[idx].kind = kind
            if !source.isEmpty { bag[idx].source = source }
        } else {
            bag.append(EntityAttribute(key: key, value: value, kind: kind, source: source))
        }
        attributes = bag
        updatedAt = Date()
    }

    /// Identity key used for de-duplication during graph discovery.
    /// Same kind + normalised label ⇒ same real-world entity.
    var dedupeKey: String { "\(kindRaw)|\(label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))" }

    var sourceURL: URL? { URL(string: sourceURLString) }
}
