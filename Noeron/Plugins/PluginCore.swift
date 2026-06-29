//
//  PluginCore.swift
//  Noeron
//
//  The plugin contract. Plugins are pure, Sendable transforms:
//      EntitySnapshot  --(network / compute)-->  PluginResult
//  The discovery engine (not the plugin) writes results into the SwiftData store,
//  so plugins never touch the model and can run off the main actor.
//

import Foundation

// MARK: - Sendable value types crossing the actor boundary

/// Immutable view of an entity handed to a plugin.
struct EntitySnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var kind: EntityKind
    var label: String
    var subtitle: String
    var attributes: [EntityAttribute]

    init(id: UUID = UUID(), kind: EntityKind, label: String, subtitle: String = "", attributes: [EntityAttribute] = []) {
        self.id = id; self.kind = kind; self.label = label; self.subtitle = subtitle; self.attributes = attributes
    }
}

extension EntitySnapshot {
    init(_ entity: Entity) {
        self.init(id: entity.id, kind: entity.kind, label: entity.label,
                  subtitle: entity.subtitle, attributes: entity.attributes)
    }
}

/// Direction of the edge a plugin proposes between the input and a finding.
enum LinkDirection: Sendable { case fromInput, toInput }

/// A node a plugin discovered, plus how it connects back to the input entity.
struct DiscoveredEntity: Sendable {
    var kind: EntityKind
    var label: String
    var subtitle: String = ""
    var confidence: Double = 0.9
    var attributes: [EntityAttribute] = []
    var sourceURL: String = ""
    var linkKind: LinkKind = .relatedTo
    var linkDirection: LinkDirection = .fromInput
}

/// A dated fact a plugin contributes to the investigation timeline.
struct DiscoveredEvent: Sendable {
    var title: String
    var date: Date
    var precision: TimelineEvent.Precision = .day
    var category: String = ""
    var detail: String = ""
}

/// Everything a single plugin run produced.
struct PluginResult: Sendable {
    var entities: [DiscoveredEntity] = []
    var events: [DiscoveredEvent] = []
    /// Facts to merge onto the *input* entity (e.g. WHOIS registrar on a domain).
    var inputAttributes: [EntityAttribute] = []
    /// First few KB of the raw response, kept for the audit log.
    var rawExcerpt: String = ""
    /// True when produced by a stubbed adapter returning sample (non-live) data.
    /// The engine flags every resulting node so analysts never mistake it for real intel.
    var sample: Bool = false

    var isEmpty: Bool { entities.isEmpty && events.isEmpty && inputAttributes.isEmpty }
    static let empty = PluginResult()
}

// MARK: - Metadata

enum PluginCategory: String, Sendable, CaseIterable {
    case network = "Network"
    case breach = "Breaches"
    case social = "Social"
    case corporate = "Corporate"
    case blockchain = "Blockchain"
    case threat = "Threat Intel"
    case knowledge = "Knowledge"
}

struct CredentialField: Sendable, Hashable {
    var key: String     // keychain account, e.g. "shodan.apiKey"
    var label: String   // UI label
    var hint: String = ""
    /// Optional fields don't gate the plugin (e.g. a host override or token that
    /// only raises a rate limit).
    var optional: Bool = false
}

/// A non-secret, user-editable plugin parameter (e.g. a custom RPC endpoint).
/// Stored in UserDefaults via `PluginParameters`, not the Keychain.
struct ParameterField: Sendable, Hashable {
    var key: String          // e.g. "eth.rpcBase"
    var label: String
    var hint: String = ""
    var placeholder: String = ""
}

struct PluginMetadata: Sendable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var category: PluginCategory
    var acceptedKinds: Set<EntityKind>
    var producesKinds: Set<EntityKind>
    var requiresAPIKey: Bool = false
    var credentialFields: [CredentialField] = []
    /// Non-secret, user-editable parameters (e.g. a custom RPC endpoint).
    var parameterFields: [ParameterField] = []
    var docURL: String = ""
    /// True when the plugin performs real network requests in this build.
    var isLive: Bool = false
    var symbol: String = "puzzlepiece.extension.fill"
}

extension PluginMetadata {
    /// Credential fields that must be filled for the plugin to run.
    var requiredCredentialFields: [CredentialField] { credentialFields.filter { !$0.optional } }

    /// Required fields with no value currently stored in the Keychain.
    var missingKeychainFields: [CredentialField] {
        guard requiresAPIKey else { return [] }
        return requiredCredentialFields.filter { !KeychainStore.has($0.key) }
    }

    /// True when every required credential is present in the Keychain.
    var isConfiguredInKeychain: Bool { missingKeychainFields.isEmpty }
}

// MARK: - Errors

enum PluginError: LocalizedError {
    case missingCredentials(String)
    case unsupportedEntity
    case network(String)
    case decoding(String)
    case rateLimited
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let s): "Missing API credentials: \(s)"
        case .unsupportedEntity: "This plugin does not accept that entity kind."
        case .network(let s): "Network error: \(s)"
        case .decoding(let s): "Could not parse response: \(s)"
        case .rateLimited: "Rate limited by the upstream service."
        case .notImplemented: "Plugin not implemented."
        }
    }
}

// MARK: - Execution context

/// Shared, thread-safe context. Immutable closures + URLSession ⇒ safe to share.
struct PluginContext: @unchecked Sendable {
    var session: URLSession
    /// Resolves a credential key (default: Keychain).
    var credentialProvider: @Sendable (String) -> String?
    /// Resolves a non-secret parameter (default: UserDefaults via PluginParameters).
    var parameterProvider: @Sendable (String) -> String?
    /// Per-host courtesy delay to stay polite with public endpoints.
    var politenessDelay: Duration = .milliseconds(150)

    init(session: URLSession = .shared,
         credentialProvider: @escaping @Sendable (String) -> String? = { KeychainStore.get($0) },
         parameterProvider: @escaping @Sendable (String) -> String? = { PluginParameters.get($0) }) {
        self.session = session
        self.credentialProvider = credentialProvider
        self.parameterProvider = parameterProvider
    }

    func credential(_ key: String) -> String? {
        let v = credentialProvider(key)
        return (v?.isEmpty == false) ? v : nil
    }

    /// A user-set parameter (e.g. custom RPC URL), or nil if unset.
    func parameter(_ key: String) -> String? {
        let v = parameterProvider(key)
        return (v?.isEmpty == false) ? v : nil
    }

    func hasCredentials(for meta: PluginMetadata) -> Bool {
        guard meta.requiresAPIKey else { return true }
        return meta.requiredCredentialFields.allSatisfy { credential($0.key) != nil }
    }
}

// MARK: - Networking helpers

extension PluginContext {
    func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Noeron/1.0 (OSINT workspace)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PluginError.network("non-HTTP response")
            }
            if http.statusCode == 429 { throw PluginError.rateLimited }
            return (data, http)
        } catch let error as PluginError {
            throw error
        } catch {
            throw PluginError.network(error.localizedDescription)
        }
    }

    func getJSON<T: Decodable>(_ type: T.Type, from url: URL, headers: [String: String] = [:]) async throws -> T {
        let (data, _) = try await get(url, headers: headers)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw PluginError.decoding(error.localizedDescription) }
    }

    func getString(from url: URL, headers: [String: String] = [:]) async throws -> String {
        let (data, _) = try await get(url, headers: headers)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Plugin protocol

protocol Plugin: Sendable {
    var metadata: PluginMetadata { get }
    /// Whether this plugin is applicable to a given entity right now.
    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool
    /// Perform the lookup. May throw `PluginError`.
    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult
}

extension Plugin {
    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool {
        metadata.acceptedKinds.contains(entity.kind) && context.hasCredentials(for: metadata)
    }
    var id: String { metadata.id }
}

// MARK: - Small helpers for plugin authors

extension String {
    func truncatedExcerpt(_ limit: Int = 4096) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}
