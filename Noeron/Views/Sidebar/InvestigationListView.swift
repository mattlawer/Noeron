//
//  InvestigationListView.swift
//  Noeron
//

import SwiftUI
import SwiftData

struct InvestigationListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Investigation.updatedAt, order: .reverse) private var investigations: [Investigation]
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Section("Investigations") {
                ForEach(investigations) { investigation in
                    InvestigationRow(investigation: investigation)
                        .tag(investigation.id)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(investigation) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Noeron")
        .overlay {
            if investigations.isEmpty {
                ContentUnavailableView {
                    Label("No Investigations", systemImage: "folder")
                } description: {
                    Text("Create your first investigation to start mapping a graph.")
                } actions: {
                    Button("New Investigation") { appState.showingNewInvestigation = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { appState.showingNewInvestigation = true } label: {
                    Label("New Investigation", systemImage: "plus")
                }
            }
            #if !os(macOS)
            ToolbarItem(placement: .topBarLeading) {
                Button { appState.showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
        }
    }

    private func delete(_ investigation: Investigation) {
        if selection == investigation.id { selection = nil }
        modelContext.delete(investigation)
        try? modelContext.save()
    }
}

private struct InvestigationRow: View {
    let investigation: Investigation
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: investigation.colorHex))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(investigation.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if !investigation.caseNumber.isEmpty {
                        Text(investigation.caseNumber)
                    }
                    Text("\(investigation.entitiesArray.count) entities")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
