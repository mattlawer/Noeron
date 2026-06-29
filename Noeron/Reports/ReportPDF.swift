//
//  ReportPDF.swift
//  Noeron
//
//  Renders the report to PDF from a SwiftUI document view (ImageRenderer), and
//  exposes a unified exporter for Markdown / HTML / PDF.
//

import SwiftUI
import CoreGraphics

@MainActor
enum ReportExporter {
    /// Raw bytes for a report in the requested format.
    static func data(for investigation: Investigation, format: ReportFormat) -> Data {
        let model = ReportModel(investigation)
        switch format {
        case .markdown: return Data(MarkdownReporter.render(model).utf8)
        case .html:     return Data(HTMLReporter.render(model).utf8)
        case .pdf:      return makePDF(ReportDocumentView(model: model))
        }
    }

    /// Convenience string for live preview (markdown / html only).
    static func previewText(for investigation: Investigation, format: ReportFormat) -> String {
        let model = ReportModel(investigation)
        switch format {
        case .markdown: return MarkdownReporter.render(model)
        case .html:     return HTMLReporter.render(model)
        case .pdf:      return "PDF preview renders on export."
        }
    }

    /// Writes the report to a temporary file and returns its URL (for share / export).
    static func writeTemporary(_ investigation: Investigation, format: ReportFormat) throws -> URL {
        let safeTitle = investigation.title.replacingOccurrences(of: "/", with: "-")
        let name = "\(safeTitle).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data(for: investigation, format: format).write(to: url, options: .atomic)
        return url
    }

    // MARK: PDF via ImageRenderer

    private static func makePDF(_ view: some View, width: CGFloat = 612) -> Data {
        let renderer = ImageRenderer(content:
            view.frame(width: width).padding(28).background(Color.white)
        )
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        let cfData = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: cfData) else { return Data() }
        var captured = Data()
        renderer.render { size, drawInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            drawInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            captured = cfData as Data
        }
        return captured
    }
}

// MARK: - Printable document view

struct ReportDocumentView: View {
    let model: ReportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title).font(.system(size: 24, weight: .bold))
                Text(metaLine).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(model.totalEntities) entities · \(model.links.count) links · \(model.events.count) events")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Rectangle().fill(Color(hex: "#21C7BC")).frame(height: 2)

            if model.hasSampleData {
                Text("⚠️ Contains sample data from un-keyed plugins.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if !model.summary.isEmpty {
                sectionTitle("Summary")
                Text(model.summary).font(.system(size: 12))
            }

            sectionTitle("Entities")
            ForEach(model.entityGroups) { group in
                Text("\(group.kind.pluralName) (\(group.entities.count))")
                    .font(.system(size: 13, weight: .semibold))
                ForEach(group.entities) { e in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(e.kind.color).frame(width: 7, height: 7).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.label).font(.system(size: 12, weight: .medium))
                            if !e.subtitle.isEmpty { Text(e.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(e.sourcePlugin.isEmpty ? "manual" : e.sourcePlugin) · \(Int(e.confidence*100))%")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }

            if !model.events.isEmpty {
                sectionTitle("Timeline")
                ForEach(model.events) { e in
                    HStack(spacing: 8) {
                        Text(e.displayDate).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        Text(e.title).font(.system(size: 11))
                        Spacer()
                    }
                }
            }

            if !model.evidence.isEmpty {
                sectionTitle("Evidence (SHA-256)")
                ForEach(model.evidence) { ev in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ev.displayName).font(.system(size: 11, weight: .medium))
                        Text(ev.sha256).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Generated by Noeron · The intelligence workspace for digital investigations.")
                .font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.black)
    }

    private var metaLine: String {
        var parts: [String] = []
        if !model.caseNumber.isEmpty { parts.append("Case \(model.caseNumber)") }
        if !model.classification.isEmpty { parts.append(model.classification) }
        parts.append("Generated \(model.generated.formatted(date: .abbreviated, time: .shortened))")
        return parts.joined(separator: " · ")
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 15, weight: .bold)).padding(.top, 8)
    }
}
