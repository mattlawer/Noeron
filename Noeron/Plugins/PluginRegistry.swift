//
//  PluginRegistry.swift
//  Noeron
//
//  The catalogue of every installed plugin (Obsidian-style). Tracks which are
//  enabled for automatic discovery and resolves the applicable set per entity.
//

import Foundation
import SwiftUI

@MainActor
final class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()

    /// All installed plugins. Order is the catalogue display order.
    let all: [any Plugin]

    /// Plugin ids enabled for automatic graph expansion.
    @Published var enabled: Set<String> {
        didSet { persistEnabled() }
    }

    private let enabledDefaultsKey = "noeron.enabledPlugins.v2"

    init(plugins: [any Plugin]? = nil) {
        let catalogue: [any Plugin] = plugins ?? PluginRegistry.defaultCatalogue
        self.all = catalogue

        if let saved = UserDefaults.standard.array(forKey: enabledDefaultsKey) as? [String] {
            self.enabled = Set(saved)
        } else {
            // Default: enable the keyless live plugins so discovery works out of the box.
            // Key-based services switch on automatically when their key is saved.
            self.enabled = Set(catalogue.filter { $0.metadata.isLive && !$0.metadata.requiresAPIKey }.map { $0.id })
        }
    }

    func enable(_ id: String) { enabled.insert(id) }
    func disable(_ id: String) { enabled.remove(id) }

    private func persistEnabled() {
        UserDefaults.standard.set(Array(enabled), forKey: enabledDefaultsKey)
    }

    // MARK: Lookup

    func plugin(id: String) -> (any Plugin)? { all.first { $0.id == id } }

    func plugins(accepting kind: EntityKind) -> [any Plugin] {
        all.filter { $0.metadata.acceptedKinds.contains(kind) }
    }

    /// Plugins that should fire during automatic discovery for the given snapshot.
    func discoveryPlugins(for entity: EntitySnapshot, context: PluginContext) -> [any Plugin] {
        all.filter { enabled.contains($0.id) && $0.canRun(on: entity, context: context) }
    }

    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func toggle(_ id: String) {
        if enabled.contains(id) { enabled.remove(id) } else { enabled.insert(id) }
    }

    var byCategory: [PluginGroup] {
        PluginCategory.allCases.compactMap { cat in
            let items = all.filter { $0.metadata.category == cat }
            return items.isEmpty ? nil : PluginGroup(category: cat, plugins: items)
        }
    }
}

/// Identifiable grouping for catalogue rendering (avoids tuple key paths in ForEach).
struct PluginGroup: Identifiable {
    let category: PluginCategory
    let plugins: [any Plugin]
    var id: String { category.rawValue }
}

// MARK: - Default catalogue

extension PluginRegistry {
    static var defaultCatalogue: [any Plugin] {
        [
            // Live, keyless
            WhoisPlugin(),
            DNSPlugin(),
            SSLCertificatePlugin(),
            IPGeolocationPlugin(),
            ASNPlugin(),
            GitHubPlugin(),

            // Live, keyless — email enrichment (no API key required)
            EmailIntelPlugin(),
            GravatarPlugin(),
            GitHubEmailPlugin(),
            EmailAccountExistencePlugin(),
            EmailRepPlugin(),

            // Live, keyless — phone & cross-platform username (no API key required)
            PhoneIntelPlugin(),
            UsernameSweepPlugin(),

            // Live, keyless — recon ported from the classic OSINT tools (no API key required)
            SubdomainEnumPlugin(),
            WaybackPlugin(),
            TyposquatPlugin(),
            IPReversePlugin(),
            URLScanPlugin(),
            GeocodePlugin(),
            CompanyRegistryPlugin(),

            // Live, keyless — free alternatives to paid services (on by default)
            XposedOrNotPlugin(),
            ShodanInternetDBPlugin(),

            // Live, keyless — blockchain / on-chain (no API key required)
            BitcoinAddressPlugin(),
            EthereumAddressPlugin(),
            SolanaAddressPlugin(),

            // Key-based — Google dorking via SerpAPI / Google Custom Search
            DorkPlugin(),

            // Key-based (stubbed adapters with realistic structured output)
            ShodanPlugin(),
            HistoricalDNSPlugin(),
            CensysPlugin(),
            HunterPlugin(),
            HaveIBeenPwnedPlugin(),
            IntelligenceXPlugin(),
            VirusTotalPlugin(),
            WikidataPlugin(),
            OpenCorporatesPlugin(),
            CompaniesHousePlugin(),
            SECPlugin(),
            RedditPlugin(),
            MastodonPlugin(),
            LinkedInPlugin(),
            BlueskyPlugin(),
            TelegramPlugin()
        ]
    }
}
