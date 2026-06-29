//
//  EvidenceViews.swift
//  Noeron
//
//  Evidence locker: import files into the managed store (hashed for chain of
//  custody), preview with QuickLook, and verify integrity.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EvidenceListView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        List {
            ForEach(investigation.evidenceArray.sorted { $0.addedAt > $1.addedAt }) { item in
                NavigationLink(value: item) { EvidenceRow(item: item) }
                    .swipeActions {
                        Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .overlay {
            if investigation.evidenceArray.isEmpty {
                ContentUnavailableView {
                    Label("No evidence", systemImage: "tray.full")
                } description: {
                    Text("Import screenshots, documents and exports. Each file is hashed (SHA-256) on import.")
                } actions: {
                    Button("Import File…") { importing = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Evidence")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .alert("Import failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error): importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    let imported = try EvidenceStore.importFile(from: url)
                    let item = EvidenceItem(displayName: imported.displayName,
                                            relativePath: imported.relativePath,
                                            contentTypeIdentifier: imported.contentType.identifier,
                                            byteCount: imported.byteCount,
                                            sha256: imported.sha256,
                                            addedBy: "Investigator")
                    modelContext.insert(item)
                    item.investigation = investigation
                    // Surface as a graph entity too.
                    let kind: EntityKind = imported.contentType.conforms(to: .image) ? .image : .document
                    let entity = Entity(kind: kind, label: imported.displayName, subtitle: imported.contentType.localizedDescription ?? "",
                                        sourcePlugin: "Evidence import")
                    modelContext.insert(entity)
                    entity.investigation = investigation
                    entity.evidence = item
                } catch {
                    importError = error.localizedDescription
                }
            }
            try? modelContext.save()
        }
    }

    private func delete(_ item: EvidenceItem) {
        if let url = item.fileURL { try? FileManager.default.removeItem(at: url) }
        modelContext.delete(item)
        try? modelContext.save()
    }
}

private struct EvidenceRow: View {
    let item: EvidenceItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).fontWeight(.medium).lineLimit(1)
                Text("\(item.byteCount.formattedBytes) · \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
    private var symbol: String {
        let type = UTType(item.contentTypeIdentifier)
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        return "doc"
    }
}

struct EvidenceDetailView: View {
    @Bindable var item: EvidenceItem
    @Environment(\.modelContext) private var modelContext
    @State private var verification: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = item.fileURL {
                    QuickLookPreview(url: url)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.2)))
                }
                SectionCard(title: "Chain of custody", systemImage: "shield.lefthalf.filled") {
                    LabeledContent("Type", value: UTType(item.contentTypeIdentifier)?.localizedDescription ?? item.contentTypeIdentifier)
                    LabeledContent("Size", value: item.byteCount.formattedBytes)
                    LabeledContent("Added", value: item.addedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Added by", value: item.addedBy.isEmpty ? "—" : item.addedBy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHA-256").foregroundStyle(.secondary)
                        Text(item.sha256).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if let v = verification {
                        Label(v, systemImage: v.hasPrefix("Verified") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(v.hasPrefix("Verified") ? .green : .red)
                    }
                    Button("Verify integrity") { verify() }.buttonStyle(.bordered)
                }
                .font(.subheadline)

                SectionCard(title: "Notes", systemImage: "note.text") {
                    TextField("Add notes about this evidence…", text: $item.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: item.notes) { _, _ in try? modelContext.save() }
                }
            }
            .padding(20)
        }
        .navigationTitle(item.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func verify() {
        guard let recomputed = EvidenceStore.recomputeHash(for: item) else {
            verification = "File missing — cannot verify"; return
        }
        verification = recomputed == item.sha256 ? "Verified — hash matches" : "MISMATCH — file altered"
    }
}
