//
//  AppEntities.swift
//  Noeron
//
//  App Intents representation of an investigation, so Shortcuts and Spotlight can
//  reference and act on them.
//

import AppIntents
import SwiftData
import Foundation

struct InvestigationAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Investigation"
    static var defaultQuery = InvestigationQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct InvestigationQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [InvestigationAppEntity] {
        let context = NoeronSchema.shared.mainContext
        let descriptor = FetchDescriptor<Investigation>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { identifiers.contains($0.id) }
            .map { InvestigationAppEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func suggestedEntities() async throws -> [InvestigationAppEntity] {
        let context = NoeronSchema.shared.mainContext
        var descriptor = FetchDescriptor<Investigation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let recents = (try? context.fetch(descriptor)) ?? []
        return recents.map { InvestigationAppEntity(id: $0.id, title: $0.title) }
    }
}
