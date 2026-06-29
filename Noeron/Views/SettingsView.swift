//
//  SettingsView.swift
//  Noeron
//
//  Tabbed settings: Plugins (catalogue → per-plugin detail/config), Discovery
//  (scope) and About. Keyless plugins work with no setup; tap a plugin to inspect
//  it, set parameters (e.g. a custom RPC) or add API credentials.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .plugins

    private enum Tab: String, CaseIterable, Identifiable {
        case plugins, discovery, about
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .plugins: "puzzlepiece.extension.fill"
            case .discovery: "slider.horizontal.3"
            case .about: "info.circle"
            }
        }
    }

    // A segmented control instead of a TabView: macOS Settings' preference-style
    // TabView tabs were not switching reliably, so this guarantees clickable tabs
    // on both platforms.
    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Label(t.title, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            // Clear the macOS window title bar (content is drawn under it).
            #if os(macOS)
            .padding(.top, 38)
            #else
            .padding(.top, 12)
            #endif

            Divider()

            Group {
                switch tab {
                case .plugins: PluginsSettingsTab()
                case .discovery: DiscoverySettingsTab()
                case .about: AboutSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .macWindowFrame(minWidth: 560, minHeight: 520)
        .toolbar {
            #if !os(macOS)
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            #endif
        }
    }
}

// MARK: - Plugins tab

private struct PluginsSettingsTab: View {
    @EnvironmentObject private var registry: PluginRegistry
    @State private var selected: PluginMetadata?

    private var keylessCount: Int { registry.all.filter { !$0.metadata.requiresAPIKey }.count }
    private var keyCount: Int { registry.all.filter { $0.metadata.requiresAPIKey }.count }
    private var configuredCount: Int { registry.all.filter { $0.metadata.requiresAPIKey && $0.metadata.isConfiguredInKeychain }.count }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    statPill("\(keylessCount)", "keyless", .green)
                    statPill("\(configuredCount)/\(keyCount)", "keys set", .orange)
                    statPill("\(registry.enabled.count)", "enabled", Theme.accent)
                }
                Text("Keyless plugins work with no setup. Tap a plugin to see its details, set parameters (like a custom RPC), or add an API key.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(registry.byCategory) { group in
                Section(group.category.rawValue) {
                    ForEach(group.plugins, id: \.metadata.id) { plugin in
                        Button { selected = plugin.metadata } label: { PluginSettingsRow(plugin: plugin) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $selected) { meta in
            NavigationStack { PluginDetailView(metadata: meta) }
                .environmentObject(registry)
        }
    }

    private func statPill(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.10)))
    }
}

private struct PluginSettingsRow: View {
    let plugin: any Plugin
    @EnvironmentObject private var registry: PluginRegistry
    private var meta: PluginMetadata { plugin.metadata }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: meta.symbol).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meta.name).fontWeight(.medium).foregroundStyle(.primary)
                    if meta.requiresAPIKey {
                        badge(meta.isConfiguredInKeychain ? "KEY SET" : "NEEDS KEY", meta.isConfiguredInKeychain ? .green : .orange)
                    } else {
                        badge("FREE", .green)
                    }
                }
                Text(meta.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { registry.isEnabled(plugin.id) },
                set: { _ in registry.toggle(plugin.id) }
            )).labelsHidden()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

// MARK: - Discovery tab

private struct DiscoverySettingsTab: View {
    @EnvironmentObject private var engine: DiscoveryEngine

    var body: some View {
        Form {
            Section("Automatic discovery") {
                Stepper(value: $engine.maxDepth, in: 1...4) {
                    LabeledContent("Max depth", value: "\(engine.maxDepth)")
                }
                Stepper(value: $engine.maxEntities, in: 25...1000, step: 25) {
                    LabeledContent("Entity cap", value: "\(engine.maxEntities)")
                }
                Text("Discovery fans out from a seed, running enabled plugins on each new node up to the depth limit, stopping at the entity cap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About tab

private struct AboutSettingsTab: View {
    var body: some View {
        Form {
            Section("Responsible use") {
                Text("Noeron is for lawful, authorised investigations using open sources. Respect platform terms, data-protection law, and the privacy of individuals.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Credential editor (used by the entity inspector's Set Up button)

struct CredentialEditor: View {
    let metadata: PluginMetadata
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(metadata.credentialFields, id: \.key) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        SecureField(field.label + (field.optional ? " (optional)" : ""), text: Binding(
                            get: { values[field.key] ?? "" },
                            set: { values[field.key] = $0 }
                        ))
                        if KeychainStore.has(field.key) {
                            Label("Saved — leave blank to keep it", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.green)
                        } else if !field.hint.isEmpty {
                            Text(field.hint).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("\(metadata.name) credentials")
            } footer: {
                if !metadata.docURL.isEmpty, let url = URL(string: metadata.docURL) {
                    Link("API documentation", destination: url).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(metadata.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var savedAny = false
                    for field in metadata.credentialFields {
                        let entered = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !entered.isEmpty { KeychainStore.set(entered, for: field.key); savedAny = true }
                    }
                    if savedAny { onSaved() }
                    dismiss()
                }
            }
        }
        .macWindowFrame(minWidth: 400, minHeight: 260)
    }
}
