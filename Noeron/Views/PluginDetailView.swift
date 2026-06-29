//
//  PluginDetailView.swift
//  Noeron
//
//  Inspect and configure a single plugin: what it accepts/produces, its docs,
//  enable state, editable parameters (e.g. a custom RPC endpoint) and API keys.
//

import SwiftUI

struct PluginDetailView: View {
    let metadata: PluginMetadata
    @EnvironmentObject private var registry: PluginRegistry
    @Environment(\.dismiss) private var dismiss

    @State private var params: [String: String] = [:]
    @State private var secrets: [String: String] = [:]
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: metadata.symbol).font(.title2).foregroundStyle(Theme.accent).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metadata.name).font(.headline)
                        HStack(spacing: 6) {
                            badge(metadata.requiresAPIKey ? "API KEY" : "FREE", metadata.requiresAPIKey ? .orange : .green)
                            badge(metadata.category.rawValue, .secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { registry.isEnabled(metadata.id) },
                        set: { _ in registry.toggle(metadata.id) }
                    )).labelsHidden()
                }
                Text(metadata.summary).font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Capabilities") {
                LabeledContent("Plugin id", value: metadata.id)
                LabeledContent("Accepts", value: kindList(metadata.acceptedKinds))
                if !metadata.producesKinds.isEmpty {
                    LabeledContent("Produces", value: kindList(metadata.producesKinds))
                }
                if !metadata.docURL.isEmpty, let url = URL(string: metadata.docURL) {
                    LabeledContent("Documentation") { Link("Open", destination: url) }
                }
            }

            if !metadata.parameterFields.isEmpty {
                Section {
                    ForEach(metadata.parameterFields, id: \.key) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            TextField(field.placeholder.isEmpty ? field.label : field.placeholder,
                                      text: paramBinding(field.key))
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            if !field.hint.isEmpty {
                                Text(field.hint).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Parameters")
                } footer: {
                    Text("Leave blank to use the default. Stored on this device, not in the investigation.")
                        .font(.caption2)
                }
            }

            if metadata.requiresAPIKey || !metadata.credentialFields.isEmpty {
                Section {
                    ForEach(metadata.credentialFields, id: \.key) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            SecureField(field.label + (field.optional ? " (optional)" : ""), text: secretBinding(field.key))
                            if KeychainStore.has(field.key) {
                                Label("Saved — leave blank to keep", systemImage: "checkmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else if !field.hint.isEmpty {
                                Text(field.hint).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("API credentials")
                } footer: {
                    Text("Keys are stored in your macOS/iOS Keychain, never in the investigation file, and read only when the plugin runs.")
                        .font(.caption2)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(metadata.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            #if os(iOS)
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            #endif
        }
        .onAppear {
            // Parameters are non-secret (UserDefaults) — safe to prefill.
            for f in metadata.parameterFields { params[f.key] = PluginParameters.get(f.key) ?? "" }
        }
    }

    private func paramBinding(_ key: String) -> Binding<String> {
        Binding(get: { params[key] ?? "" }, set: { params[key] = $0 })
    }
    private func secretBinding(_ key: String) -> Binding<String> {
        Binding(get: { secrets[key] ?? "" }, set: { secrets[key] = $0 })
    }

    private func save() {
        for f in metadata.parameterFields { PluginParameters.set(params[f.key], for: f.key) }
        var savedKey = false
        for f in metadata.credentialFields {
            let entered = (secrets[f.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !entered.isEmpty { KeychainStore.set(entered, for: f.key); savedKey = true }
        }
        if savedKey { registry.enable(metadata.id) }
        saved = true
        dismiss()
    }

    private func kindList(_ kinds: Set<EntityKind>) -> String {
        kinds.map(\.displayName).sorted().joined(separator: ", ")
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}
