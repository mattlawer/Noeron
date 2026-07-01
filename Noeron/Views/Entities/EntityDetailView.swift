//
//  EntityDetailView.swift
//  Noeron
//
//  The entity inspector: provenance, facts, linked neighbours, related timeline,
//  and the plugin runner (run all configured plugins, or one on demand) with the
//  live discovery log underneath.
//

import SwiftUI
import SwiftData

struct EntityDetailView: View {
    @Bindable var entity: Entity
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: DiscoveryEngine
    @EnvironmentObject private var registry: PluginRegistry

    @State private var runError: RunError?
    @State private var credentialSheet: PluginMetadata?
    @State private var pluginDetail: PluginMetadata?
    @State private var showMerge = false

    /// A failed manual run that the user can fix by entering credentials.
    private struct RunError: Identifiable {
        let id = UUID()
        let plugin: PluginMetadata
        let message: String
    }

    private var relatedEvents: [TimelineEvent] {
        investigation.eventsArray.filter { $0.entity?.id == entity.id }
    }
    private var applicablePlugins: [any Plugin] {
        registry.plugins(accepting: entity.kind)
    }

    /// Most recent run of a plugin against *this* entity, if any.
    private func lastRun(_ pluginID: String) -> PluginRun? {
        (investigation.pluginRuns ?? [])
            .filter { $0.pluginID == pluginID && $0.targetLabel == entity.label }
            .max { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                provenanceSection
                reviewSection
                if !entity.attributes.isEmpty { attributesSection }
                if entity.degree > 0 { neighboursSection }
                if !relatedEvents.isEmpty { eventsSection }
                pluginsSection
            }
            .padding(20)
        }
        .navigationTitle(entity.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { entity.pinned.toggle() } label: {
                    Image(systemName: entity.pinned ? "pin.fill" : "pin")
                }
            }
        }
        .sheet(item: $credentialSheet) { meta in
            NavigationStack {
                CredentialEditor(metadata: meta) {
                    registry.enable(meta.id)
                    runError = nil
                }
            }
        }
        .sheet(item: $pluginDetail) { meta in
            NavigationStack { PluginDetailView(metadata: meta) }
        }
        .sheet(isPresented: $showMerge) {
            NavigationStack {
                List(mergeCandidates, id: \.id) { candidate in
                    Button { merge(into: candidate) } label: {
                        HStack(spacing: 10) {
                            KindBadge(kind: candidate.kind).scaleEffect(0.8).frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.label).fontWeight(.medium)
                                if !candidate.subtitle.isEmpty {
                                    Text(candidate.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Merge “\(entity.label)” into…")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showMerge = false } } }
            }
            .macWindowFrame(minWidth: 380, minHeight: 420)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            KindBadge(kind: entity.kind).scaleEffect(1.4).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entity.label).font(.title2.bold()).textSelection(.enabled)
                    CopyButton(value: entity.label, hint: "Copy \(entity.kind.displayName.lowercased())")
                }
                Text(entity.kind.displayName + (entity.subtitle.isEmpty ? "" : " · \(entity.subtitle)"))
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ConfidenceDot(confidence: entity.confidence)
                    Text("Confidence \(Int(entity.confidence * 100))%").font(.caption).foregroundStyle(.secondary)
                    if entity.isSeed { Label("Seed", systemImage: "scope").font(.caption).foregroundStyle(Theme.accent) }
                }
            }
            Spacer()
        }
    }

    private var attributesSection: some View {
        SectionCard(title: "Facts", systemImage: "list.bullet.rectangle") {
            ForEach(entity.attributes) { attr in
                HStack(alignment: .firstTextBaseline) {
                    Text(attr.key).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                    if attr.kind == .url, let url = URL(string: attr.value) {
                        Link(attr.value, destination: url).lineLimit(1)
                    } else {
                        Text(attr.value).textSelection(.enabled)
                    }
                    Spacer()
                    if !attr.source.isEmpty {
                        Text(attr.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if attr.kind != .boolean {
                        CopyButton(value: attr.value, hint: "Copy value")
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var neighboursSection: some View {
        SectionCard(title: "Linked entities (\(entity.degree))", systemImage: "link") {
            ForEach(linkRows, id: \.id) { row in
                NavigationLink(value: row.other) {
                    HStack(spacing: 8) {
                        Image(systemName: row.directionSymbol).font(.caption).foregroundStyle(.secondary)
                        Text(row.label).font(.caption).foregroundStyle(.secondary)
                        KindBadge(kind: row.other.kind).scaleEffect(0.7).frame(width: 20, height: 20)
                        Text(row.other.label).fontWeight(.medium).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct LinkRow: Identifiable { let id: UUID; let label: String; let other: Entity; let directionSymbol: String }
    private var linkRows: [LinkRow] {
        var rows: [LinkRow] = []
        for link in entity.outgoing { if let t = link.target, !t.discarded {
            rows.append(.init(id: link.id, label: link.label, other: t, directionSymbol: "arrow.right"))
        } }
        for link in entity.incoming { if let s = link.source, !s.discarded {
            rows.append(.init(id: link.id, label: link.label, other: s, directionSymbol: "arrow.left"))
        } }
        return rows
    }

    private var eventsSection: some View {
        SectionCard(title: "Timeline", systemImage: "calendar") {
            ForEach(relatedEvents.sorted { $0.date < $1.date }) { event in
                HStack {
                    Text(event.displayDate).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(event.title).font(.subheadline)
                    Spacer()
                }
            }
        }
    }

    // MARK: Plugins

    private var pluginsSection: some View {
        SectionCard(title: "Plugins", systemImage: "puzzlepiece.extension") {
            // Run-all (auto-expand) action.
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await engine.expand(seed: entity, in: investigation, modelContext: modelContext) }
                } label: {
                    Label("Run all plugins (auto-expand)", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(engine.isRunning || applicablePlugins.isEmpty)
                Text("Runs every enabled plugin that accepts this \(entity.kind.displayName.lowercased()), then expands the new findings.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            if let error = runError { missingConfigBanner(error) }

            ForEach(applicablePlugins, id: \.metadata.id) { plugin in
                pluginRow(plugin)
            }

            // Live discovery log, shown under the plugin list.
            DiscoveryProgressView()
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func pluginRow(_ plugin: any Plugin) -> some View {
        let meta = plugin.metadata
        let needsSetup = meta.requiresAPIKey && !meta.isConfiguredInKeychain
        let run = lastRun(meta.id)
        HStack(spacing: 8) {
            Button { pluginDetail = meta } label: {
                Image(systemName: meta.symbol).foregroundStyle(Theme.accent).frame(width: 22)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(meta.name).fontWeight(.medium)
                    if meta.requiresAPIKey {
                        Image(systemName: meta.isConfiguredInKeychain ? "key.fill" : "key")
                            .font(.caption2)
                            .foregroundStyle(meta.isConfiguredInKeychain ? .green : .orange)
                    }
                }
                if let run {
                    HStack(spacing: 4) {
                        Image(systemName: statusSymbol(run.status)).foregroundStyle(statusColor(run.status)).font(.caption2)
                        Text("Ran \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not run yet").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if needsSetup {
                Button("Set Up") { credentialSheet = meta }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("Run") { runPlugin(plugin) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(engine.isRunning)
            }
        }
        .font(.subheadline)
        .contentShape(Rectangle())
    }

    private func statusSymbol(_ s: PluginRun.Status) -> String {
        switch s { case .success: "checkmark.circle.fill"; case .empty: "minus.circle"; case .failed: "xmark.circle.fill"; case .running: "clock" }
    }
    private func statusColor(_ s: PluginRun.Status) -> Color {
        switch s { case .success: .green; case .empty: .secondary; case .failed: .red; case .running: .orange }
    }

    /// Inline error with a one-tap fix that opens the plugin's credential editor.
    private func missingConfigBanner(_ error: RunError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(error.message).font(.caption).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Button("Enter API Key") { credentialSheet = error.plugin }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Dismiss") { runError = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.4)))
    }

    private func runPlugin(_ plugin: any Plugin) {
        let meta = plugin.metadata
        let missing = meta.missingKeychainFields
        if !missing.isEmpty {
            let fields = missing.map(\.label).joined(separator: ", ")
            runError = RunError(plugin: meta, message: "\(meta.name) needs \(fields) to run. Add it to continue.")
            return
        }
        runError = nil
        Task { @MainActor in
            await engine.runSingle(plugin: plugin, on: entity, in: investigation, modelContext: modelContext)
            if let last = engine.lastError, meta.requiresAPIKey,
               ["credential", "key", "rejected", "unauthor", "401", "403"].contains(where: { last.localizedCaseInsensitiveContains($0) }) {
                runError = RunError(plugin: meta, message: "\(meta.name): \(last)")
            }
        }
    }

    // MARK: Analyst review — adjust confidence or discard a false positive

    private var reviewSection: some View {
        SectionCard(title: "Analyst review", systemImage: "checkmark.seal") {
            HStack {
                Text("Confidence").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(entity.confidence * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.confidenceColor(entity.confidence))
            }
            Slider(
                value: Binding(
                    get: { entity.confidence },
                    set: { entity.confidence = $0; entity.updatedAt = Date(); try? modelContext.save() }
                ),
                in: 0...1, step: 0.05
            )
            .tint(Theme.confidenceColor(entity.confidence))

            HStack(spacing: 8) {
                Button(role: .destructive) { discard() } label: {
                    Label("Discard", systemImage: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
                if !mergeCandidates.isEmpty {
                    Button { showMerge = true } label: {
                        Label("Merge into…", systemImage: "arrow.triangle.merge")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(.top, 2)
            Text("Discard hides this false positive and stops discovery re-adding it. Merge folds it into another \(entity.kind.displayName.lowercased()), moving its links and facts.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    /// Same-kind entities this one could be merged into.
    private var mergeCandidates: [Entity] {
        investigation.entitiesArray
            .filter { $0.kind == entity.kind && $0.id != entity.id }
            .sorted { $0.label < $1.label }
    }

    private func merge(into target: Entity) {
        showMerge = false
        let src = entity
        dismiss()   // leave the page before the source is deleted
        DispatchQueue.main.async {
            EntityMerge.merge(src, into: target, in: investigation, context: modelContext)
        }
    }

    /// Mark the entity as a discarded false positive (hidden everywhere and skipped
    /// by future discovery), then leave the page. Reversible: it's flagged, not deleted.
    private func discard() {
        entity.discarded = true
        entity.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }

    @ViewBuilder
    private var provenanceSection: some View {
        SectionCard(title: "Provenance", systemImage: "shield.lefthalf.filled") {
            LabeledContent("Source", value: entity.sourcePlugin.isEmpty ? "Manual" : entity.sourcePlugin)
            LabeledContent("Added", value: entity.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let url = entity.sourceURL {
                LabeledContent("Reference") { Link(url.absoluteString, destination: url).lineLimit(1) }
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Reusable card

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1, y: 1))
    }
}
