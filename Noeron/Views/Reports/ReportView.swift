//
//  ReportView.swift
//  Noeron
//
//  Generate and export court-ready reports in Markdown, HTML or PDF.
//

import SwiftUI

struct ReportView: View {
    @Bindable var investigation: Investigation
    @State private var format: ReportFormat = .markdown
    @State private var preview: String = ""
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            previewArea
        }
        .navigationTitle("Reports")
        .onAppear(perform: regenerate)
        .onChange(of: format) { _, _ in regenerate() }
    }

    private var controls: some View {
        HStack {
            Picker("Format", selection: $format) {
                ForEach(ReportFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            if let url = exportURL {
                ShareLink(item: url) { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var previewArea: some View {
        ScrollView {
            if format == .pdf {
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("PDF is generated on export.").foregroundStyle(.secondary)
                    Text("\(ReportModel(investigation).totalEntities) entities · \(investigation.linksArray.count) links")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(Theme.panel.opacity(0.4))
        .alert("Export failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func regenerate() {
        preview = ReportExporter.previewText(for: investigation, format: format)
        do { exportURL = try ReportExporter.writeTemporary(investigation, format: format) }
        catch { exportError = error.localizedDescription }
    }
}
