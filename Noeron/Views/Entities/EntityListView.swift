//
//  EntityListView.swift
//  Noeron
//
//  All entities of one kind inside an investigation, with search and quick add.
//

import SwiftUI
import SwiftData

struct EntityListView: View {
    @Bindable var investigation: Investigation
    let kind: EntityKind
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var showAdd = false

    private var entities: [Entity] {
        let all = investigation.entities(of: kind)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.label.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(entities) { entity in
                NavigationLink(value: entity) { EntityRow(entity: entity) }
                    .swipeActions {
                        Button(role: .destructive) { delete(entity) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .searchable(text: $query, prompt: "Search \(kind.pluralName.lowercased())")
        .overlay {
            if entities.isEmpty {
                ContentUnavailableView("No \(kind.pluralName)", systemImage: kind.symbolName,
                                       description: Text("Add one, or run discovery from the Overview."))
            }
        }
        .navigationTitle(kind.pluralName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEntitySheet(investigation: investigation, presetKind: kind)
        }
    }

    private func delete(_ entity: Entity) {
        modelContext.delete(entity)
        try? modelContext.save()
    }
}
