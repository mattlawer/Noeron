//
//  ReportView.swift
//  Noeron
//
//  Generate and export court-ready reports in Markdown, HTML or PDF.
//  Scope to the whole investigation or a selected subgraph, and choose whether
//  to embed discarded entities and a confidence floor.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ReportView: View {
    @Bindable var investigation: Investigation
    @State private var format: ReportFormat = .markdown
    @State private var preview: String = ""
    @State private var exportURL: URL?
    @State private var exportError: String?

    // Scope & content options.
    @State private var useSubgraph = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var includeDiscarded = false
    @State private var minConfidence: Double = 0
    @State private var showingPicker = false

    private var options: ReportOptions {
        ReportOptions(scope: useSubgraph ? .subgraph(selectedIDs) : .all,
                      includeDiscarded: includeDiscarded,
                      minConfidence: minConfidence)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            optionsBar
            Divider()
            previewArea
        }
        .navigationTitle("Reports")
        .onAppear { defaultSelectionIfNeeded(); regenerate() }
        .onChange(of: format) { _, _ in regenerate() }
        .onChange(of: options) { _, _ in regenerate() }
        .sheet(isPresented: $showingPicker) {
            EntityScopePicker(investigation: investigation, selection: $selectedIDs)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Picker("Format", selection: $format) {
                ForEach(ReportFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            exportButton
        }
        .padding(12)
    }

    @ViewBuilder
    private var exportButton: some View {
        let disabled = useSubgraph && selectedIDs.isEmpty
        #if os(macOS)
        // Native save panel — write straight to a chosen location on disk.
        Button { saveToDisk() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
        #else
        if let url = exportURL, !disabled {
            ShareLink(item: url) { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
        }
        #endif
    }

    #if os(macOS)
    private func saveToDisk() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ReportExporter.suggestedFileName(investigation, format: format, options: options)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReportExporter.data(for: investigation, format: format, options: options)
                .write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
    #endif

    private var optionsBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { scopeControls }
            VStack(alignment: .leading, spacing: 10) { scopeControls }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var scopeControls: some View {
        Picker("Scope", selection: $useSubgraph) {
            Text("Full investigation").tag(false)
            Text("Selected subgraph").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)

        if useSubgraph {
            Button {
                defaultSelectionIfNeeded(force: true)
                showingPicker = true
            } label: {
                Label("\(selectedIDs.count) selected", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
        }

        Toggle("Include discarded", isOn: $includeDiscarded)
            .toggleStyle(.switch)
            .fixedSize()

        HStack(spacing: 6) {
            Text("Min conf.").font(.caption).foregroundStyle(.secondary)
            Slider(value: $minConfidence, in: 0...1).frame(width: 120)
            Text("\(Int(minConfidence * 100))%").font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ScrollView {
            if useSubgraph && selectedIDs.isEmpty {
                ContentUnavailableView("No entities selected",
                                       systemImage: "checklist",
                                       description: Text("Choose entities to include in the subgraph report."))
                    .padding(.top, 50)
            } else if format == .pdf {
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("PDF is generated on export.").foregroundStyle(.secondary)
                    let m = ReportModel(investigation, options: options)
                    Text("\(m.totalEntities) entities · \(m.links.count) links")
                        .font(.caption).foregroundStyle(.secondary)
                    if m.averageConfidence > 0 {
                        Text("avg confidence \(Int(m.averageConfidence * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(Theme.panel.opacity(0.4))
        .alert("Export failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    /// Seed the selection with all active entities the first time it's needed.
    private func defaultSelectionIfNeeded(force: Bool = false) {
        guard force ? selectedIDs.isEmpty : (useSubgraph && selectedIDs.isEmpty) else { return }
        selectedIDs = Set(investigation.entitiesArray.map(\.id))
    }

    private func regenerate() {
        preview = ReportExporter.previewText(for: investigation, format: format, options: options)
        #if !os(macOS)
        // The share sheet needs a file URL up-front; macOS writes on demand via the save panel.
        do { exportURL = try ReportExporter.writeTemporary(investigation, format: format, options: options) }
        catch { exportError = error.localizedDescription }
        #endif
    }
}

// MARK: - Entity scope picker

/// Checklist of the investigation's entities (grouped by kind) that drives a
/// subgraph report. Discarded entities are shown but flagged.
private struct EntityScopePicker: View {
    let investigation: Investigation
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    private var groups: [EntityKindGroup] {
        let byKind = Dictionary(grouping: investigation.allEntitiesArray, by: { $0.kind })
        return EntityKind.sidebarOrder.compactMap { kind in
            guard let members = byKind[kind], !members.isEmpty else { return nil }
            return EntityKindGroup(kind: kind, entities: members.sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.kind.pluralName) {
                        ForEach(group.entities) { e in
                            Button { toggle(e.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selection.contains(e.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selection.contains(e.id) ? Theme.accent : .secondary)
                                    Image(systemName: e.kind.symbolName).foregroundStyle(e.kind.color).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.label).strikethrough(e.discarded)
                                        if !e.subtitle.isEmpty {
                                            Text(e.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if e.discarded {
                                        Text("discarded").font(.caption2).foregroundStyle(.red)
                                    }
                                    Text("\(Int(e.confidence * 100))%")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Select entities")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu("Select") {
                        Button("All") { selection = Set(investigation.allEntitiesArray.map(\.id)) }
                        Button("None") { selection = [] }
                        Button("Active only") { selection = Set(investigation.entitiesArray.map(\.id)) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}
