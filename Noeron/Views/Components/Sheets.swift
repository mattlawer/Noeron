//
//  Sheets.swift
//  Noeron
//
//  Modal forms: create investigation, add entity.
//

import SwiftUI
import SwiftData

struct NewInvestigationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var onCreate: (UUID) -> Void

    @State private var title = ""
    @State private var caseNumber = ""
    @State private var classification = "Investigation"
    @State private var summary = ""
    @State private var colorHex = "#21C7BC"

    private let palette = ["#21C7BC", "#5B8DEF", "#E8A13A", "#F85149", "#BC8CFF", "#3FB950"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Case number (optional)", text: $caseNumber)
                    TextField("Classification", text: $classification)
                }
                Section("Summary") {
                    TextField("What is this investigation about?", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Colour") {
                    HStack {
                        ForEach(palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }
            }
            .navigationTitle("New Investigation")
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .macWindowFrame(minWidth: 420, minHeight: 420)
    }

    private func create() {
        let investigation = Investigation(title: title.trimmingCharacters(in: .whitespaces),
                                          summary: summary, caseNumber: caseNumber,
                                          classification: classification)
        investigation.colorHex = colorHex
        modelContext.insert(investigation)
        try? modelContext.save()
        onCreate(investigation.id)
        dismiss()
    }
}

struct AddEntitySheet: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: DiscoveryEngine

    var presetKind: EntityKind = .email
    @State private var kind: EntityKind = .email
    @State private var label = ""
    @State private var subtitle = ""
    @State private var discoverAfter = true

    private let kinds = EntityKind.sidebarOrder

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Kind", selection: $kind) {
                        ForEach(kinds, id: \.self) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                }
                Section("Value") {
                    TextField(placeholder, text: $label)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Note / subtitle (optional)", text: $subtitle)
                }
                Section {
                    Toggle("Run automatic discovery after adding", isOn: $discoverAfter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Entity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { kind = presetKind }
        }
        .macWindowFrame(minWidth: 420, minHeight: 380)
    }

    private var placeholder: String {
        switch kind {
        case .email: "name@example.com"
        case .domain: "example.com"
        case .ipAddress: "185.199.108.153"
        case .username: "@handle"
        case .cryptoWallet: "bc1q… or 0x…"
        case .phone: "+1 555 010 0000"
        default: kind.displayName
        }
    }

    private func add() {
        let normalized = Normalizer.label(for: kind, label)
        let entity = Entity(kind: kind, label: normalized, subtitle: subtitle, isSeed: true, sourcePlugin: "Manual entry")
        modelContext.insert(entity)
        entity.investigation = investigation
        try? modelContext.save()
        let shouldDiscover = discoverAfter
        dismiss()
        if shouldDiscover {
            Task { await engine.expand(seed: entity, in: investigation, modelContext: modelContext) }
        }
    }
}
