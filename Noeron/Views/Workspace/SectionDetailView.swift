//
//  SectionDetailView.swift
//  Noeron
//
//  Routes the selected workspace section to its content view, inside a single
//  NavigationStack so any list can push the entity / evidence inspectors.
//

import SwiftUI

struct SectionDetailView: View {
    @Bindable var investigation: Investigation
    let section: WorkspaceSection

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Entity.self) { entity in
                    EntityDetailView(entity: entity, investigation: investigation)
                }
                .navigationDestination(for: EvidenceItem.self) { item in
                    EvidenceDetailView(item: item)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:        OverviewView(investigation: investigation)
        case .kind(let kind):  EntityListView(investigation: investigation, kind: kind)
        case .timeline:        TimelineView(investigation: investigation)
        case .graph:           GraphCanvasView(investigation: investigation)
        case .evidence:        EvidenceListView(investigation: investigation)
        case .notes:           NotesView(investigation: investigation)
        case .reports:         ReportView(investigation: investigation)
        case .pluginLog:       PluginLogView(investigation: investigation)
        }
    }
}
