//
//  NotesAndLogViews.swift
//  Noeron
//
//  Free-form Markdown notes + the plugin-run audit log.
//

import SwiftUI
import SwiftData

// MARK: - Notes

struct NotesView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(investigation.notesArray.sorted { $0.updatedAt > $1.updatedAt }) { note in
                NoteCard(note: note)
                    .swipeActions {
                        Button(role: .destructive) { modelContext.delete(note); try? modelContext.save() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .overlay {
            if investigation.notesArray.isEmpty {
                ContentUnavailableView("No notes", systemImage: "note.text",
                                       description: Text("Capture hypotheses and observations in Markdown."))
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addNote() } label: { Label("New Note", systemImage: "plus") }
            }
        }
    }

    private func addNote() {
        let note = NoteItem(title: "New note", body: "")
        modelContext.insert(note)
        note.investigation = investigation
        try? modelContext.save()
    }
}

private struct NoteCard: View {
    @Bindable var note: NoteItem
    @Environment(\.modelContext) private var modelContext
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $note.title)
                .font(.headline)
                .onChange(of: note.title) { _, _ in note.updatedAt = Date(); try? modelContext.save() }

            if editing {
                TextField("Write in Markdown…", text: $note.body, axis: .vertical)
                    .lineLimit(4...20)
                    .font(.body.monospaced())
                    .onChange(of: note.body) { _, _ in note.updatedAt = Date(); try? modelContext.save() }
            } else if !note.body.isEmpty {
                Text(LocalizedStringKey(note.body)).font(.subheadline)
            } else {
                Text("Empty note").font(.subheadline).foregroundStyle(.tertiary)
            }

            HStack {
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(editing ? "Done" : "Edit") { editing.toggle() }.font(.caption).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plugin audit log

struct PluginLogView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext

    private var runs: [PluginRun] {
        (investigation.pluginRuns ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            ForEach(runs) { run in PluginRunRow(run: run) }
        }
        .overlay {
            if runs.isEmpty {
                ContentUnavailableView("No plugin activity", systemImage: "list.bullet.rectangle",
                                       description: Text("Every plugin execution is logged here for provenance."))
            }
        }
        .navigationTitle("Plugin Log")
        .toolbar {
            if !runs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { clear() } label: { Label("Clear", systemImage: "trash") }
                }
            }
        }
    }

    private func clear() {
        for run in runs { modelContext.delete(run) }
        try? modelContext.save()
    }
}

private struct PluginRunRow: View {
    let run: PluginRun
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(run.pluginName).fontWeight(.medium)
                Text("→ \(run.targetLabel)").foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if run.discoveredEntities > 0 { Text("+\(run.discoveredEntities)").foregroundStyle(.secondary) }
                if let d = run.duration { Text(String(format: "%.1fs", d)).font(.caption2).foregroundStyle(.tertiary) }
            }
            .font(.subheadline)
            if !run.message.isEmpty {
                Text(run.message).font(.caption).foregroundStyle(run.status == .failed ? .red : .secondary)
            }
            if !run.rawExcerpt.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    Text(run.rawExcerpt).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                } label: {
                    Text("Raw response").font(.caption2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch run.status { case .success: "checkmark.circle.fill"; case .empty: "minus.circle"; case .failed: "xmark.circle.fill"; case .running: "clock" }
    }
    private var color: Color {
        switch run.status { case .success: .green; case .empty: .secondary; case .failed: .red; case .running: .orange }
    }
}
