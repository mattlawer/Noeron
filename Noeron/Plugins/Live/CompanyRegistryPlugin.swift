//
//  CompanyRegistryPlugin.swift
//  Noeron
//
//  Keyless company / legal-registry lookup. For France it queries the official
//  government open API (recherche-entreprises.api.gouv.fr — no key) to return the
//  SIREN/SIRET, head office, registration date and directors, then links the
//  canonical legal-document pages (Pappers, Societe.com, Annuaire des Entreprises).
//  For other countries it emits search links into the national registries so an
//  analyst is one click from the official record.
//
//  Registry document links are emitted as `.document` nodes so they don't trigger
//  further crawling — they're references, not pivots.
//

import Foundation

struct CompanyRegistryPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "company-registry",
            name: "Company Registry",
            summary: "Legal-registry data & documents for a company. France: official keyless gov API (SIREN/SIRET, address, directors) + Pappers/Societe.com. Other countries: direct registry search links.",
            category: .corporate,
            acceptedKinds: [.company],
            producesKinds: [.person, .location],
            requiresAPIKey: false,
            docURL: "https://recherche-entreprises.api.gouv.fr/docs",
            isLive: true,
            symbol: "building.columns.fill"
        )
    }

    // MARK: French government open API (keyless)

    private struct FRSearch: Decodable {
        let results: [Company]?
        struct Company: Decodable {
            let siren: String?
            let nom_complet: String?
            let nom_raison_sociale: String?
            let date_creation: String?
            let activite_principale: String?
            let siege: Siege?
            let dirigeants: [Dirigeant]?
            struct Siege: Decodable {
                let siret: String?; let adresse: String?
                let code_postal: String?; let libelle_commune: String?
            }
            struct Dirigeant: Decodable {
                let nom: String?; let prenoms: String?; let denomination: String?
                let qualite: String?; let type_dirigeant: String?
            }
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let name = entity.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else { throw PluginError.unsupportedEntity }
        var result = PluginResult()

        await lookupFrance(name: name, context: context, into: &result)
        if result.isEmpty { result.rawExcerpt = "No registry match for \(name)" }
        return result
    }

    /// Enrich with the French registry record if a confident match is found.
    private func lookupFrance(name: String, context: PluginContext, into result: inout PluginResult) async {
        var comps = URLComponents(string: "https://recherche-entreprises.api.gouv.fr/search")!
        comps.queryItems = [.init(name: "q", value: name), .init(name: "per_page", value: "1")]
        guard let url = comps.url,
              let search = try? await context.getJSON(FRSearch.self, from: url),
              let company = search.results?.first,
              let siren = company.siren else { return }

        // Guard against loose matches: the registry name must align with the query.
        let canonical = company.nom_complet ?? company.nom_raison_sociale ?? ""
        guard Self.namesAlign(name, canonical) else { return }

        result.rawExcerpt = "FR registry: \(canonical) — SIREN \(siren)"
        result.inputAttributes.append(.init(key: "SIREN", value: siren, source: "data.gouv.fr"))
        if let siret = company.siege?.siret { result.inputAttributes.append(.init(key: "SIRET (siège)", value: siret, source: "data.gouv.fr")) }
        if let naf = company.activite_principale { result.inputAttributes.append(.init(key: "Activity (NAF)", value: naf, source: "data.gouv.fr")) }
        if let d = ISO8601Date.parse(company.date_creation) {
            if let raw = company.date_creation {
                result.inputAttributes.append(.init(key: "Registered", value: String(raw.prefix(10)), kind: .date, source: "data.gouv.fr"))
            }
            result.events.append(.init(title: "Company registered: \(canonical)", date: d, precision: .day, category: "Corporate", detail: "SIREN \(siren)"))
        }

        // Head office → location.
        if let siege = company.siege {
            let addr = [siege.adresse, siege.code_postal, siege.libelle_commune].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
            if !addr.isEmpty {
                result.entities.append(.init(kind: .location, label: addr, subtitle: "Head office (RCS)",
                                             confidence: 0.7, linkKind: .relatedTo, linkDirection: .fromInput))
            }
        }

        // Directors / officers.
        for d in (company.dirigeants ?? []).prefix(8) {
            if (d.type_dirigeant ?? "").lowercased().contains("morale"), let denom = d.denomination, !denom.isEmpty {
                continue // corporate officer; skip to avoid name-clash noise
            }
            let person = [d.prenoms, d.nom].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !person.isEmpty else { continue }
            result.entities.append(.init(kind: .person, label: person, subtitle: d.qualite ?? "Director",
                                         confidence: 0.7, linkKind: .employs, linkDirection: .fromInput))
        }

        // Direct record pages for this exact SIREN — kept as clickable attributes
        // (not document nodes). Real documents are surfaced by the Google Dorks
        // plugin; a registry *search* URL carries no information, so we don't emit one.
        result.inputAttributes.append(.init(key: "Annuaire (gouv.fr)", value: "https://annuaire-entreprises.data.gouv.fr/entreprise/\(siren)", kind: .url, source: "Company Registry"))
        result.inputAttributes.append(.init(key: "Pappers", value: "https://www.pappers.fr/entreprise/\(siren)", kind: .url, source: "Company Registry"))
        result.inputAttributes.append(.init(key: "Societe.com", value: "https://www.societe.com/societe/\(siren).html", kind: .url, source: "Company Registry"))
    }

    // MARK: Name matching

    private static func namesAlign(_ query: String, _ registry: String) -> Bool {
        func norm(_ s: String) -> String {
            s.folding(options: .diacriticInsensitive, locale: .init(identifier: "fr"))
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let a = norm(query), b = norm(registry)
        guard a.count >= 2, !b.isEmpty else { return false }
        return a == b || b.contains(a) || a.contains(b)
    }
}
