//
//  ReportBuilder.swift
//  Noeron
//
//  Builds a structured report model from an investigation and renders it to
//  Markdown and HTML (court-ready: provenance, evidence hashes, plugin audit log).
//  PDF is produced from the SwiftUI report view in ReportPDF.swift.
//

import Foundation
import CoreGraphics

enum ReportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"
    case pdf = "PDF"
    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : rawValue.lowercased() }
}

/// Identifiable grouping of entities by kind (avoids tuple key paths in ForEach).
struct EntityKindGroup: Identifiable {
    let kind: EntityKind
    let entities: [Entity]
    var id: String { kind.rawValue }
}

/// What to include when building a report.
struct ReportOptions: Equatable {
    enum Scope: Equatable {
        case all
        /// Only the named entities and the links induced between them.
        case subgraph(Set<UUID>)
    }

    var scope: Scope = .all
    /// Include discarded (false-positive) entities, flagged as such.
    var includeDiscarded: Bool = false
    /// Drop non-discarded entities below this confidence (0 = keep everything).
    var minConfidence: Double = 0

    static let `default` = ReportOptions()

    var isSubgraph: Bool { if case .subgraph = scope { return true }; return false }
}

/// Snapshot of everything that goes into a report, captured on the main actor.
struct ReportModel {
    let title: String
    let caseNumber: String
    let classification: String
    let summary: String
    let generated: Date
    let options: ReportOptions
    let entityGroups: [EntityKindGroup]
    let links: [EntityLink]
    let events: [TimelineEvent]
    let evidence: [EvidenceItem]
    let runs: [PluginRun]
    let nodePositions: [(id: UUID, point: CGPoint, kind: EntityKind, label: String)]

    @MainActor
    init(_ investigation: Investigation, options: ReportOptions = .default) {
        self.options = options
        title = investigation.title
        caseNumber = investigation.caseNumber
        classification = investigation.classification
        summary = investigation.summary
        generated = Date()

        // Resolve the included entity set from scope + discard + confidence filters.
        var pool = investigation.allEntitiesArray
        if case .subgraph(let ids) = options.scope { pool = pool.filter { ids.contains($0.id) } }
        if !options.includeDiscarded { pool = pool.filter { !$0.discarded } }
        if options.minConfidence > 0 {
            // Keep discarded regardless — when shown, they carry their own flag.
            pool = pool.filter { $0.discarded || $0.confidence >= options.minConfidence }
        }
        let includedIDs = Set(pool.map { $0.id })

        let byKind = Dictionary(grouping: pool, by: { $0.kind })
        entityGroups = EntityKind.sidebarOrder.compactMap { kind in
            guard let members = byKind[kind], !members.isEmpty else { return nil }
            let sorted = members.sorted { a, b in
                if a.discarded != b.discarded { return !a.discarded }   // active first
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
            return EntityKindGroup(kind: kind, entities: sorted)
        }

        // Induced links: both endpoints must be inside the included set.
        links = investigation.linksArray.filter { l in
            guard let s = l.source?.id, let t = l.target?.id else { return false }
            return includedIDs.contains(s) && includedIDs.contains(t)
        }

        // Timeline: whole investigation for a full report; only events tied to an
        // included entity when scoped to a subgraph.
        if options.isSubgraph {
            events = investigation.eventsArray.filter { ev in
                if let id = ev.entity?.id { return includedIDs.contains(id) }
                return false
            }
        } else {
            events = investigation.eventsArray
        }

        // Chain-of-custody evidence and the plugin audit log are never trimmed.
        evidence = investigation.evidenceArray
        runs = (investigation.pluginRuns ?? []).sorted { $0.startedAt > $1.startedAt }
        nodePositions = pool.map {
            (id: $0.id,
             point: CGPoint(x: $0.canvasX, y: $0.canvasY),
             kind: $0.kind, label: $0.label)
        }
    }

    var includedEntities: [Entity] { entityGroups.flatMap { $0.entities } }
    var totalEntities: Int { includedEntities.count }
    var discardedCount: Int { includedEntities.reduce(0) { $0 + ($1.discarded ? 1 : 0) } }
    var averageConfidence: Double {
        let active = includedEntities.filter { !$0.discarded }
        guard !active.isEmpty else { return 0 }
        return active.map(\.confidence).reduce(0, +) / Double(active.count)
    }
    var hasSampleData: Bool { runs.contains { $0.message.localizedCaseInsensitiveContains("sample") } }

    /// Human-readable description of what this report covers.
    var scopeLabel: String {
        var s = options.isSubgraph ? "Selected subgraph" : "Full investigation"
        if options.includeDiscarded && discardedCount > 0 { s += " · incl. \(discardedCount) discarded" }
        if options.minConfidence > 0 { s += " · ≥\(Int(options.minConfidence * 100))% confidence" }
        return s
    }
}

// MARK: - Markdown

enum MarkdownReporter {
    /// Five-cell text meter, e.g. `▓▓▓░░`.
    static func confidenceBar(_ c: Double) -> String {
        let filled = max(0, min(5, Int((c * 5).rounded())))
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: 5 - filled)
    }

    static func render(_ m: ReportModel) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
        var out = ""
        out += "# \(m.title)\n\n"
        if !m.caseNumber.isEmpty { out += "**Case:** \(m.caseNumber)  \n" }
        if !m.classification.isEmpty { out += "**Classification:** \(m.classification)  \n" }
        out += "**Generated:** \(df.string(from: m.generated))  \n"
        out += "**Scope:** \(m.scopeLabel)  \n"
        out += "**Contents:** \(m.totalEntities) entities · \(m.links.count) links · \(m.events.count) timeline events"
        if m.averageConfidence > 0 { out += " · avg confidence \(Int(m.averageConfidence * 100))%" }
        out += "\n\n"
        if !m.summary.isEmpty { out += "## Summary\n\n\(m.summary)\n\n" }
        if m.hasSampleData {
            out += "> ⚠️ This report contains **sample** data from un-keyed plugins. Configure API keys for verified results.\n\n"
        }

        out += "## Entities\n\n"
        for group in m.entityGroups {
            out += "### \(group.kind.pluralName) (\(group.entities.count))\n\n"
            for e in group.entities {
                let name = e.discarded ? "~~\(e.label)~~" : "**\(e.label)**"
                out += "- \(name)"
                if !e.subtitle.isEmpty { out += " — \(e.subtitle)" }
                out += "  _(source: \(e.sourcePlugin.isEmpty ? "manual" : e.sourcePlugin), confidence \(confidenceBar(e.confidence)) \(Int(e.confidence * 100))%"
                if e.discarded { out += ", ⚠︎ discarded" }
                out += ")_\n"
                for a in e.attributes { out += "    - \(a.key): \(a.value)\n" }
            }
            out += "\n"
        }

        if !m.links.isEmpty {
            out += "## Relationships\n\n"
            for l in m.links {
                let s = l.source?.label ?? "?", t = l.target?.label ?? "?"
                out += "- \(s) — *\(l.label)* → \(t)  _(\(l.sourcePlugin.isEmpty ? "manual" : l.sourcePlugin))_\n"
            }
            out += "\n"
        }

        if !m.events.isEmpty {
            out += "## Timeline\n\n"
            for e in m.events { out += "- **\(e.displayDate)** — \(e.title)\(e.category.isEmpty ? "" : " *(\(e.category))*")\n" }
            out += "\n"
        }

        if !m.evidence.isEmpty {
            out += "## Evidence\n\n| File | Type | Size | SHA-256 |\n|---|---|---|---|\n"
            for ev in m.evidence {
                out += "| \(ev.displayName) | \(ev.contentTypeIdentifier) | \(ev.byteCount.formattedBytes) | `\(ev.sha256)` |\n"
            }
            out += "\n"
        }

        out += "## Provenance — plugin runs\n\n"
        for r in m.runs.prefix(100) {
            out += "- \(r.startedAt.formatted(date: .abbreviated, time: .standard)) · **\(r.pluginName)** on \(r.targetLabel) → \(r.statusRaw)"
            if r.discoveredEntities > 0 { out += " (+\(r.discoveredEntities))" }
            if !r.message.isEmpty { out += " — \(r.message)" }
            out += "\n"
        }
        out += "\n---\n_Generated by Noeron · The intelligence workspace for digital investigations._\n"
        return out
    }
}

// MARK: - HTML

enum HTMLReporter {
    static func render(_ m: ReportModel) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
        var body = ""
        body += "<header><h1>\(esc(m.title))</h1><p class='meta'>"
        if !m.caseNumber.isEmpty { body += "Case \(esc(m.caseNumber)) · " }
        if !m.classification.isEmpty { body += "\(esc(m.classification)) · " }
        body += "Generated \(esc(df.string(from: m.generated)))</p>"
        body += "<p class='scope'><strong>\(esc(m.scopeLabel))</strong></p>"
        var scope = "\(m.totalEntities) entities · \(m.links.count) links · \(m.events.count) events"
        if m.averageConfidence > 0 { scope += " · avg confidence \(Int(m.averageConfidence * 100))%" }
        body += "<p class='scope'>\(scope)</p></header>"

        if m.hasSampleData {
            body += "<div class='warn'>⚠️ Contains sample data from un-keyed plugins. Configure API keys for verified results.</div>"
        }
        if !m.summary.isEmpty { body += "<section><h2>Summary</h2><p>\(esc(m.summary))</p></section>" }

        body += "<section><h2>Graph</h2>\(svg(m))</section>"

        body += "<section><h2>Entities</h2>"
        for g in m.entityGroups {
            body += "<h3>\(esc(g.kind.pluralName)) (\(g.entities.count))</h3><ul class='entities'>"
            for e in g.entities {
                body += "<li class='\(e.discarded ? "discarded" : "")'><span class='dot' style='background:\(g.kind.colorHex)'></span><strong>\(esc(e.label))</strong>"
                if e.discarded { body += " <span class='badge'>discarded</span>" }
                if !e.subtitle.isEmpty { body += " — \(esc(e.subtitle))" }
                body += " <span class='conf' title='\(Int(e.confidence*100))% confidence'><i style='width:\(Int(e.confidence*100))%'></i></span>"
                body += " <span class='src'>\(esc(e.sourcePlugin.isEmpty ? "manual" : e.sourcePlugin)) · \(Int(e.confidence*100))%</span>"
                if !e.attributes.isEmpty {
                    body += "<ul class='attrs'>"
                    for a in e.attributes { body += "<li>\(esc(a.key)): \(esc(a.value))</li>" }
                    body += "</ul>"
                }
                body += "</li>"
            }
            body += "</ul>"
        }
        body += "</section>"

        if !m.events.isEmpty {
            body += "<section><h2>Timeline</h2><ul class='timeline'>"
            for e in m.events { body += "<li><time>\(esc(e.displayDate))</time> \(esc(e.title)) <span class='src'>\(esc(e.category))</span></li>" }
            body += "</ul></section>"
        }

        if !m.evidence.isEmpty {
            body += "<section><h2>Evidence</h2><table><tr><th>File</th><th>Type</th><th>Size</th><th>SHA-256</th></tr>"
            for ev in m.evidence {
                body += "<tr><td>\(esc(ev.displayName))</td><td>\(esc(ev.contentTypeIdentifier))</td><td>\(ev.byteCount.formattedBytes)</td><td class='hash'>\(esc(ev.sha256))</td></tr>"
            }
            body += "</table></section>"
        }

        body += "<section><h2>Provenance</h2><table><tr><th>Time</th><th>Plugin</th><th>Target</th><th>Result</th></tr>"
        for r in m.runs.prefix(100) {
            body += "<tr><td>\(esc(r.startedAt.formatted(date: .numeric, time: .standard)))</td><td>\(esc(r.pluginName))</td><td>\(esc(r.targetLabel))</td><td>\(esc(r.statusRaw))\(r.discoveredEntities > 0 ? " +\(r.discoveredEntities)" : "")</td></tr>"
        }
        body += "</table></section>"
        body += "<footer>Generated by Noeron — The intelligence workspace for digital investigations.</footer>"

        return """
        <!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <title>\(esc(m.title)) — Noeron Report</title>
        <style>\(css)</style></head><body>\(body)</body></html>
        """
    }

    /// Inline SVG node-link diagram from persisted canvas positions.
    private static func svg(_ m: ReportModel) -> String {
        let pts = m.nodePositions.filter { $0.point != .zero }
        guard pts.count > 1 else { return "<p class='src'>Run the graph view to generate a layout.</p>" }
        let xs = pts.map { $0.point.x }, ys = pts.map { $0.point.y }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let pad: CGFloat = 40
        func tx(_ x: CGFloat) -> CGFloat { (x - minX) / w * 720 + pad }
        func ty(_ y: CGFloat) -> CGFloat { (y - minY) / h * 460 + pad }
        let lookup = Dictionary(uniqueKeysWithValues: m.nodePositions.map { ($0.id, $0) })

        var s = "<svg viewBox='0 0 800 540' class='graph' xmlns='http://www.w3.org/2000/svg'>"
        for l in m.links {
            guard let a = l.source?.id, let b = l.target?.id,
                  let pa = lookup[a], let pb = lookup[b], pa.point != .zero, pb.point != .zero else { continue }
            s += "<line x1='\(tx(pa.point.x))' y1='\(ty(pa.point.y))' x2='\(tx(pb.point.x))' y2='\(ty(pb.point.y))' stroke='#888' stroke-width='1' opacity='0.5'/>"
        }
        for p in pts {
            s += "<circle cx='\(tx(p.point.x))' cy='\(ty(p.point.y))' r='7' fill='\(p.kind.colorHex)'/>"
            s += "<text x='\(tx(p.point.x) + 10)' y='\(ty(p.point.y) + 4)' font-size='10' fill='#333'>\(esc(String(p.label.prefix(28))))</text>"
        }
        s += "</svg>"
        return s
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1b1f24; max-width: 880px; margin: 0 auto; padding: 32px; }
    header h1 { margin: 0 0 4px; font-size: 28px; }
    .meta, .scope, .src { color: #6a737d; font-size: 13px; }
    h2 { border-bottom: 2px solid #21c7bc; padding-bottom: 4px; margin-top: 32px; }
    h3 { margin-top: 18px; color: #24292f; }
    .warn { background: #fff3cd; border: 1px solid #ffe08a; padding: 10px 14px; border-radius: 8px; margin: 16px 0; }
    ul.entities { list-style: none; padding-left: 0; }
    ul.entities > li { padding: 6px 0; border-bottom: 1px solid #eee; }
    ul.entities > li.discarded { opacity: 0.55; }
    ul.entities > li.discarded > strong { text-decoration: line-through; }
    .badge { display: inline-block; font-size: 10px; text-transform: uppercase; letter-spacing: 0.03em; color: #b42318; background: #fee4e2; border-radius: 4px; padding: 1px 5px; margin-left: 4px; vertical-align: middle; }
    .conf { display: inline-block; width: 44px; height: 6px; border-radius: 3px; background: #e1e4e8; vertical-align: middle; margin: 0 4px; overflow: hidden; }
    .conf > i { display: block; height: 100%; background: #21c7bc; }
    .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }
    ul.attrs { color: #57606a; font-size: 13px; margin: 4px 0 4px 22px; }
    ul.timeline { list-style: none; padding-left: 0; }
    ul.timeline time { font-family: ui-monospace, monospace; color: #21c7bc; margin-right: 8px; }
    table { border-collapse: collapse; width: 100%; font-size: 13px; }
    th, td { border: 1px solid #e1e4e8; padding: 6px 8px; text-align: left; }
    th { background: #f6f8fa; }
    .hash { font-family: ui-monospace, monospace; font-size: 11px; word-break: break-all; }
    .graph { width: 100%; height: auto; border: 1px solid #eee; border-radius: 8px; background: #fafbfc; }
    footer { margin-top: 40px; color: #6a737d; font-size: 12px; border-top: 1px solid #eee; padding-top: 12px; }
    """
}
