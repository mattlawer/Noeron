//
//  OverviewView.swift
//  Noeron
//
//  Investigation home: the automatic-discovery entry point + at-a-glance stats.
//  Paste a selector (email / domain / IP / @handle / wallet) and the graph builds
//  itself by fanning out the enabled plugins.
//

import SwiftUI
import SwiftData

struct OverviewView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: DiscoveryEngine
    @EnvironmentObject private var appState: AppState

    @State private var seedText = ""
    @State private var typedRows: [TypedSeed] = [TypedSeed()]
    @State private var showAddEntity = false
    @AppStorage("noeron.onboardingDismissed") private var onboardingDismissed = false

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    /// One explicitly-typed selector row in the discovery input.
    struct TypedSeed: Identifiable {
        let id = UUID()
        var kind: EntityKind = .email
        var value: String = ""
    }

    /// Kinds offered as seeds (selectors people actually start an investigation from).
    private let seedKinds: [EntityKind] = [.email, .phone, .username, .domain, .ipAddress,
                                           .person, .company, .cryptoWallet, .socialProfile, .url]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !onboardingDismissed { onboardingBanner }
                discoveryCard
                DiscoveryProgressView()
                statsGrid
                if let recent = recentRuns, !recent.isEmpty { recentActivity(recent) }
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddEntity = true } label: { Label("Add Entity", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAddEntity) {
            AddEntitySheet(investigation: investigation)
        }
    }

    // MARK: Onboarding

    private var onboardingBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Getting started").font(.subheadline.weight(.semibold))
                Text("Type or paste a selector — an email, domain, @username, IP or wallet — then tap **Discover**. Noeron runs its keyless plugins and builds the graph automatically. Tap any node to dig deeper, run more plugins, or discard false positives.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { withAnimation { onboardingDismissed = true } } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.30)))
    }

    // MARK: Discovery card

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Automatic discovery", systemImage: "wand.and.stars")
                .font(.headline)
            Text("Enter one or more selectors, choosing the type for each, and/or paste free text. “Discover” seeds them all and expands the whole graph in one run.")
                .font(.subheadline).foregroundStyle(.secondary)

            // Typed selectors — explicit value + type per row.
            VStack(spacing: 10) {
                ForEach($typedRows) { $row in
                    typedRow($row)
                }
                Button {
                    typedRows.append(TypedSeed(kind: typedRows.last?.kind ?? .email))
                } label: {
                    Label("Add selector", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.panel.opacity(0.6))
                    TextEditor(text: $seedText)
                        .font(.body.monospaced())
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if seedText.isEmpty {
                        Text("john@example.com  example.com\n185.199.108.153  @handle")
                            .font(.callout.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 72)
                let preview = EntityExtractor.extract(from: seedText)
                if !preview.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(preview, id: \.self) { ex in EntityChip(kind: ex.kind, label: ex.value) }
                        }
                    }
                }
            } label: {
                Text("Or paste free text").font(.subheadline.weight(.medium))
            }
            .tint(.secondary)

            Button {
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
                Task { await runDiscovery() }
            } label: {
                Label("Discover", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasSeedInput || engine.isRunning)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background).shadow(radius: 1, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.25)))
    }

    /// One typed-selector row: a compact type menu + a full-width value field.
    @ViewBuilder
    private func typedRow(_ row: Binding<TypedSeed>) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(seedKinds, id: \.self) { k in
                    Button {
                        row.wrappedValue.kind = k
                    } label: {
                        Label(k.displayName, systemImage: k.symbolName)
                        if row.wrappedValue.kind == k { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: row.wrappedValue.kind.symbolName)
                    Text(row.wrappedValue.kind.displayName).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(row.wrappedValue.kind.color)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: 132, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(row.wrappedValue.kind.color.opacity(0.16)))
            }
            .buttonStyle(.plain)

            TextField(placeholder(for: row.wrappedValue.kind), text: row.value)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType(for: row.wrappedValue.kind))
                .submitLabel(.done)
                #endif

            if typedRows.count > 1 || !row.wrappedValue.value.isEmpty {
                Button {
                    typedRows.removeAll { $0.id == row.wrappedValue.id }
                    if typedRows.isEmpty { typedRows = [TypedSeed()] }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hasSeedInput: Bool {
        !seedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || typedRows.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func placeholder(for kind: EntityKind) -> String {
        switch kind {
        case .email: "name@example.com"
        case .phone: "+1 555 010 0000"
        case .username: "@handle"
        case .domain: "example.com"
        case .ipAddress: "185.199.108.153"
        case .person: "Jane Doe"
        case .company: "Acme Ltd"
        case .cryptoWallet: "bc1q… or 0x…"
        case .url: "https://…"
        default: kind.displayName
        }
    }

    #if os(iOS)
    private func keyboardType(for kind: EntityKind) -> UIKeyboardType {
        switch kind {
        case .email: .emailAddress
        case .phone: .phonePad
        case .url, .domain: .URL
        default: .default
        }
    }
    #endif


    // MARK: Stats

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "Entities", value: investigation.entitiesArray.count, symbol: "circle.grid.3x3.fill", tint: Theme.accent)
                StatCard(title: "Links", value: investigation.linksArray.count, symbol: "link", tint: .blue)
                StatCard(title: "Events", value: investigation.eventsArray.count, symbol: "calendar", tint: .orange)
                StatCard(title: "Evidence", value: investigation.evidenceArray.count, symbol: "tray.full", tint: .purple)
                ForEach(investigation.populatedKinds, id: \.self) { kind in
                    StatCard(title: kind.pluralName, value: investigation.count(of: kind), symbol: kind.symbolName, tint: kind.color)
                }
            }
        }
    }

    private var recentRuns: [PluginRun]? {
        investigation.pluginRuns?.sorted { $0.startedAt > $1.startedAt }
    }

    private func recentActivity(_ runs: [PluginRun]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent plugin activity").font(.headline)
            ForEach(runs.prefix(6)) { run in
                HStack {
                    Image(systemName: statusSymbol(run.status))
                        .foregroundStyle(statusColor(run.status))
                    Text(run.pluginName).fontWeight(.medium)
                    Text("on \(run.targetLabel)").foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if run.discoveredEntities > 0 { Text("+\(run.discoveredEntities)").foregroundStyle(.secondary) }
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1, y: 1))
    }

    private func statusSymbol(_ s: PluginRun.Status) -> String {
        switch s { case .success: "checkmark.circle.fill"; case .empty: "minus.circle"; case .failed: "xmark.circle.fill"; case .running: "clock" }
    }
    private func statusColor(_ s: PluginRun.Status) -> Color {
        switch s { case .success: .green; case .empty: .secondary; case .failed: .red; case .running: .orange }
    }

    // MARK: Actions

    private func runDiscovery() async {
        // 1. Explicitly-typed rows take their kind verbatim from the user.
        var selectors: [ExtractedEntity] = typedRows.compactMap { row in
            let v = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : ExtractedEntity(kind: row.kind, value: v)
        }
        // 2. Pasted free text is auto-extracted (or treated as one best-guess selector).
        let pasted = EntityExtractor.extract(from: seedText)
        if pasted.isEmpty {
            let trimmed = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                selectors.append(.init(kind: EntityExtractor.classifySingle(trimmed), value: trimmed))
            }
        } else {
            selectors.append(contentsOf: pasted)
        }
        guard !selectors.isEmpty else { return }

        // 3. De-duplicate by (kind, normalized label) and resolve to entities.
        var seeds: [Entity] = []
        var seen = Set<String>()
        for ex in selectors {
            let label = Normalizer.label(for: ex.kind, ex.value)
            guard !label.isEmpty, seen.insert("\(ex.kind.rawValue)|\(label.lowercased())").inserted else { continue }
            if let existing = investigation.entitiesArray.first(where: {
                $0.kind == ex.kind && $0.label.caseInsensitiveCompare(label) == .orderedSame
            }) {
                seeds.append(existing)
            } else {
                let entity = Entity(kind: ex.kind, label: label, isSeed: true, sourcePlugin: "Manual entry")
                modelContext.insert(entity)
                entity.investigation = investigation
                seeds.append(entity)
            }
        }
        try? modelContext.save()
        seedText = ""
        typedRows = [TypedSeed()]

        // 4. One shared expansion run across every seed.
        await engine.expand(seeds: seeds, in: investigation, modelContext: modelContext)
        appState.selectedSection = .graph
    }
}

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: Int
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1, y: 1))
    }
}
