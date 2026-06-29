//
//  SECPlugin.swift
//  Noeron
//
//  SEC EDGAR (keyless): US public-company CIK and recent filings (10-K, 8-K…).
//

import Foundation

struct SECPlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "sec", name: "SEC EDGAR",
              summary: "US public-company CIK and recent filings (10-K, 8-K…).",
              category: .corporate, acceptedKinds: [.company],
              producesKinds: [.document],
              requiresAPIKey: false,
              docURL: "https://www.sec.gov/edgar/sec-api-documentation", isLive: true, symbol: "doc.richtext")
    }

    // SEC requires a descriptive User-Agent with contact info.
    private let ua = "Noeron OSINT (research; contact: osint@noeron.app)"

    private struct Ticker: Decodable { let cik_str: Int?; let ticker: String?; let title: String? }
    private struct Submissions: Decodable {
        let name: String?
        let filings: Filings?
        struct Filings: Decodable { let recent: Recent? }
        struct Recent: Decodable {
            let form: [String]?; let filingDate: [String]?; let primaryDocument: [String]?; let accessionNumber: [String]?
        }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let tickers = try await context.getJSON([String: Ticker].self,
                                                from: URL(string: "https://www.sec.gov/files/company_tickers.json")!,
                                                headers: ["User-Agent": ua])
        let q = entity.label.lowercased()
        guard let match = tickers.values.first(where: { ($0.title ?? "").lowercased().contains(q) }) ?? tickers.values
                .first(where: { q.contains(($0.title ?? "###").lowercased()) }),
              let cik = match.cik_str else { return .empty }

        let cik10 = String(format: "%010d", cik)
        var result = PluginResult(rawExcerpt: "SEC CIK \(cik10) — \(match.title ?? "")")
        result.inputAttributes.append(.init(key: "CIK", value: cik10, source: "SEC"))
        if let ticker = match.ticker { result.inputAttributes.append(.init(key: "Ticker", value: ticker, source: "SEC")) }

        let subs = try await context.getJSON(Submissions.self,
                                              from: URL(string: "https://data.sec.gov/submissions/CIK\(cik10).json")!,
                                              headers: ["User-Agent": ua])
        if let recent = subs.filings?.recent, let forms = recent.form {
            var added = 0
            for i in forms.indices where added < 8 {
                let form = forms[i]
                guard ["10-K", "10-Q", "8-K", "S-1", "DEF 14A"].contains(form) else { continue }
                let date = recent.filingDate?[safe: i] ?? ""
                let accession = recent.accessionNumber?[safe: i]?.replacingOccurrences(of: "-", with: "") ?? ""
                let docURL = "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=\(cik10)&type=\(form)"
                result.entities.append(.init(kind: .document, label: "\(form) (\(date))", subtitle: "SEC filing",
                                             confidence: 0.8, sourceURL: docURL, linkKind: .relatedTo, linkDirection: .fromInput))
                if let d = ISO8601Date.parse(date) {
                    result.events.append(.init(title: "\(form) filed: \(match.title ?? entity.label)", date: d, category: "SEC filing"))
                }
                _ = accession
                added += 1
            }
        }
        return result
    }
}
