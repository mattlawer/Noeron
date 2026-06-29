//
//  WorkspaceNavigator.swift
//  Noeron
//
//  Section navigator for one investigation: overview, populated entity kinds,
//  timeline, graph, evidence, notes, reports, and the plugin audit log.
//

import SwiftUI

struct WorkspaceNavigator: View {
    @Bindable var investigation: Investigation
    @Binding var selection: WorkspaceSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.overview, badge: nil)
            }

            if !investigation.populatedKinds.isEmpty {
                Section("Entities") {
                    ForEach(investigation.populatedKinds, id: \.self) { kind in
                        row(.kind(kind), badge: investigation.count(of: kind), tint: kind.color)
                    }
                }
            }

            Section("Views") {
                row(.graph, badge: investigation.linksArray.count)
                row(.timeline, badge: investigation.eventsArray.count)
            }

            Section("Material") {
                row(.evidence, badge: investigation.evidenceArray.count)
                row(.notes, badge: investigation.notesArray.count)
            }

            Section("Output") {
                row(.reports, badge: nil)
                row(.pluginLog, badge: investigation.pluginRuns?.count ?? 0)
            }
        }
        .navigationTitle(investigation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func row(_ section: WorkspaceSection, badge: Int?, tint: Color = Theme.accent) -> some View {
        Label {
            HStack {
                Text(section.title)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: section.symbol).foregroundStyle(tint)
        }
        .tag(section)
    }
}
