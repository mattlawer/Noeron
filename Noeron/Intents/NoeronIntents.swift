//
//  NoeronIntents.swift
//  Noeron
//
//  App Intents + Siri / Spotlight Shortcuts:
//    • Create Investigation
//    • Add Selector (extract kind, optionally auto-discover)
//    • Open Investigation (deep links into the workspace)
//

import AppIntents
import SwiftData
import Foundation

// MARK: - Create Investigation

struct CreateInvestigationIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Investigation"
    static var description = IntentDescription("Start a new Noeron investigation workspace.")

    @Parameter(title: "Title") var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<InvestigationAppEntity> & ProvidesDialog {
        let context = NoeronSchema.shared.mainContext
        let investigation = Investigation(title: title)
        context.insert(investigation)
        try? context.save()
        SpotlightIndexer.shared.index(investigation)
        return .result(value: InvestigationAppEntity(id: investigation.id, title: investigation.title),
                       dialog: "Created investigation “\(title)”.")
    }
}

// MARK: - Add Selector

struct AddSelectorIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Selector"
    static var description = IntentDescription("Add an email, domain, IP, handle or wallet and optionally expand the graph.")

    @Parameter(title: "Selector") var selector: String
    @Parameter(title: "Investigation") var investigation: InvestigationAppEntity?
    @Parameter(title: "Run discovery", default: true) var discover: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = NoeronSchema.shared.mainContext
        let target = try resolveInvestigation(in: context)

        let kind = EntityExtractor.classifySingle(selector)
        let label = Normalizer.label(for: kind, selector)
        let entity = Entity(kind: kind, label: label, isSeed: true, sourcePlugin: "Shortcut")
        context.insert(entity)
        entity.investigation = target
        try? context.save()
        SpotlightIndexer.shared.index(entity)

        if discover {
            let engine = DiscoveryEngine()
            await engine.expand(seed: entity, in: target, modelContext: context, maxDepth: 1)
            return .result(dialog: "Added \(label) and discovered \(engine.discovered) linked entit\(engine.discovered == 1 ? "y" : "ies").")
        }
        return .result(dialog: "Added \(label) to “\(target.title)”.")
    }

    @MainActor
    private func resolveInvestigation(in context: ModelContext) throws -> Investigation {
        if let investigation {
            // Bind to a plain UUID local so #Predicate captures it as a value,
            // not as a key path into InvestigationAppEntity.
            let targetID = investigation.id
            if let found = try? context.fetch(FetchDescriptor<Investigation>(predicate: #Predicate { $0.id == targetID })).first {
                return found
            }
        }
        // Fall back to the most recent, or create a capture inbox.
        var descriptor = FetchDescriptor<Investigation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let recent = try? context.fetch(descriptor).first { return recent }
        let inbox = Investigation(title: "Quick Capture")
        context.insert(inbox)
        return inbox
    }
}

// MARK: - Open Investigation

struct OpenInvestigationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Investigation"
    static var openAppWhenRun = true

    @Parameter(title: "Investigation") var investigation: InvestigationAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.route(.investigation(investigation.id))
        return .result()
    }
}

// MARK: - Shortcuts

struct NoeronShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddSelectorIntent(),
                    phrases: ["Add a selector to \(.applicationName)",
                              "Capture a lead in \(.applicationName)"],
                    shortTitle: "Add Selector",
                    systemImageName: "plus.viewfinder")
        AppShortcut(intent: CreateInvestigationIntent(),
                    phrases: ["Start a new \(.applicationName) investigation"],
                    shortTitle: "New Investigation",
                    systemImageName: "folder.badge.plus")
        AppShortcut(intent: OpenInvestigationIntent(),
                    phrases: ["Open an investigation in \(.applicationName)"],
                    shortTitle: "Open Investigation",
                    systemImageName: "folder")
    }
}
