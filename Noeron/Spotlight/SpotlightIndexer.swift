//
//  SpotlightIndexer.swift
//  Noeron
//
//  Mirrors investigations and entities into the system Spotlight index so analysts
//  can find a domain, email or case straight from the OS search field. Tapping a
//  result deep-links back into the workspace (handled in NoeronApp).
//

import Foundation
import CoreSpotlight
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    static let domainEntity = "com.noeron.app.entity"
    static let domainInvestigation = "com.noeron.app.investigation"

    private weak var container: ModelContainer?
    private let index = CSSearchableIndex.default()

    func attach(container: ModelContainer) { self.container = container }

    // MARK: Identifiers

    static func entityIdentifier(_ id: UUID) -> String { "entity:\(id.uuidString)" }
    static func investigationIdentifier(_ id: UUID) -> String { "inv:\(id.uuidString)" }

    static func entityID(from identifier: String) -> UUID? {
        identifier.hasPrefix("entity:") ? UUID(uuidString: String(identifier.dropFirst(7))) : nil
    }
    static func investigationID(from identifier: String) -> UUID? {
        identifier.hasPrefix("inv:") ? UUID(uuidString: String(identifier.dropFirst(4))) : nil
    }

    // MARK: Bulk reindex

    func reindexAll() async {
        guard let container else { return }
        let context = container.mainContext
        var items: [CSSearchableItem] = []

        if let investigations = try? context.fetch(FetchDescriptor<Investigation>()) {
            for inv in investigations { items.append(makeItem(for: inv)) }
        }
        if let entities = try? context.fetch(FetchDescriptor<Entity>()) {
            for entity in entities { items.append(makeItem(for: entity)) }
        }
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }

    // MARK: Incremental

    func index(_ entity: Entity) {
        index.indexSearchableItems([makeItem(for: entity)]) { _ in }
    }
    func index(_ investigation: Investigation) {
        index.indexSearchableItems([makeItem(for: investigation)]) { _ in }
    }
    func remove(entityID: UUID) {
        index.deleteSearchableItems(withIdentifiers: [Self.entityIdentifier(entityID)]) { _ in }
    }

    // MARK: Builders

    private func makeItem(for entity: Entity) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = entity.label
        attrs.contentDescription = "\(entity.kind.displayName)\(entity.subtitle.isEmpty ? "" : " · \(entity.subtitle)")"
        attrs.keywords = [entity.kind.displayName, entity.label] + entity.attributes.map(\.value)
        attrs.contentCreationDate = entity.createdAt
        return CSSearchableItem(uniqueIdentifier: Self.entityIdentifier(entity.id),
                                domainIdentifier: Self.domainEntity,
                                attributeSet: attrs)
    }

    private func makeItem(for investigation: Investigation) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = investigation.title
        attrs.contentDescription = investigation.summary.isEmpty
            ? "Investigation · \(investigation.entitiesArray.count) entities"
            : investigation.summary
        attrs.keywords = ["investigation", investigation.caseNumber, investigation.classification].filter { !$0.isEmpty }
        attrs.contentCreationDate = investigation.createdAt
        return CSSearchableItem(uniqueIdentifier: Self.investigationIdentifier(investigation.id),
                                domainIdentifier: Self.domainInvestigation,
                                attributeSet: attrs)
    }
}
