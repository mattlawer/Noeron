//
//  Investigation.swift
//  Noeron
//
//  An investigation is a self-contained workspace: entities, links, notes,
//  evidence, timeline events and the audit log of every plugin run.
//
//  CloudKit rules honoured throughout the model layer:
//   • every stored property has a default value
//   • every relationship is optional (to-many are optional arrays)
//   • no `.unique` attributes (unsupported by the CloudKit mirror)
//

import Foundation
import SwiftData

@Model
final class Investigation {
    var id: UUID = UUID()
    var title: String = "Untitled Investigation"
    var summary: String = ""
    var caseNumber: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var colorHex: String = "#21C7BC"
    var isArchived: Bool = false

    /// Free-form classification, e.g. "Due diligence", "Threat intel", "Journalism".
    var classification: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Entity.investigation)
    var entities: [Entity]? = []

    @Relationship(deleteRule: .cascade, inverse: \EntityLink.investigation)
    var links: [EntityLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteItem.investigation)
    var notes: [NoteItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \EvidenceItem.investigation)
    var evidence: [EvidenceItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.investigation)
    var events: [TimelineEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \PluginRun.investigation)
    var pluginRuns: [PluginRun]? = []

    @Relationship(deleteRule: .cascade, inverse: \Tag.investigation)
    var tags: [Tag]? = []

    init(title: String = "Untitled Investigation",
         summary: String = "",
         caseNumber: String = "",
         classification: String = "") {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.caseNumber = caseNumber
        self.classification = classification
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Convenience

extension Investigation {
    var entitiesArray: [Entity] { entities ?? [] }
    var linksArray: [EntityLink] { links ?? [] }
    var notesArray: [NoteItem] { notes ?? [] }
    var evidenceArray: [EvidenceItem] { evidence ?? [] }
    var eventsArray: [TimelineEvent] { (events ?? []).sorted { $0.date < $1.date } }
    var tagsArray: [Tag] { tags ?? [] }

    func entities(of kind: EntityKind) -> [Entity] {
        entitiesArray.filter { $0.kind == kind }.sorted { $0.label < $1.label }
    }

    func count(of kind: EntityKind) -> Int {
        entitiesArray.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) }
    }

    /// Kinds that currently have at least one entity, in sidebar order.
    var populatedKinds: [EntityKind] {
        EntityKind.sidebarOrder.filter { count(of: $0) > 0 }
    }

    func touch() { updatedAt = Date() }
}
