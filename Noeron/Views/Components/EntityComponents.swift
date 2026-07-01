//
//  EntityComponents.swift
//  Noeron
//
//  Small reusable views: entity chip, entity row, confidence dot, kind badge.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform clipboard write.
enum Clipboard {
    static func copy(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }
}

/// A compact copy-to-clipboard button (two-squares glyph) with a brief tick on success.
struct CopyButton: View {
    let value: String
    var hint: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            Clipboard.copy(value)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run { withAnimation(.easeInOut(duration: 0.2)) { copied = false } }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : hint)
        #if os(macOS)
        .focusable(false)
        #endif
    }
}

/// Live auto-expand progress: current step + an auto-scrolling log of every step.
/// Shown on every screen that can launch discovery so the process is transparent.
struct DiscoveryProgressView: View {
    @EnvironmentObject private var engine: DiscoveryEngine

    var body: some View {
        if engine.isRunning || !engine.liveLog.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                stepLog
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1, y: 1))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            if engine.isRunning { ProgressView().controlSize(.small) }
            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            Text(engine.isRunning ? engine.statusText : "Discovery complete")
                .font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer()
            Text("\(engine.processed) processed · \(engine.discovered) found")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if engine.isRunning {
                Button(role: .destructive) { engine.cancel() } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var stepLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.liveLog) { line in
                        DiscoveryStepRow(line: line).id(line.id)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 170)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel.opacity(0.5)))
            .onChange(of: engine.liveLog.count) { _, _ in
                if let last = engine.liveLog.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}

private struct DiscoveryStepRow: View {
    let line: DiscoveryEngine.LogLine
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: line.isError ? "exclamationmark.triangle.fill" : "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(line.isError ? Color.red : Color.secondary.opacity(0.6))
                .padding(.top, 2)
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(line.isError ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EntityChip: View {
    let kind: EntityKind
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName).font(.caption2)
            Text(label).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(kind.color.opacity(0.18)))
        .foregroundStyle(kind.color)
    }
}

struct KindBadge: View {
    let kind: EntityKind
    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(kind.color))
    }
}

struct ConfidenceDot: View {
    let confidence: Double
    var body: some View {
        Circle()
            .fill(Theme.confidenceColor(confidence))
            .frame(width: 8, height: 8)
            .help("Confidence \(Int(confidence * 100))%")
    }
}

struct EntityRow: View {
    let entity: Entity
    var body: some View {
        HStack(spacing: 10) {
            KindBadge(kind: entity.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entity.label).fontWeight(.medium).lineLimit(1)
                    if entity.isSeed {
                        Image(systemName: "scope").font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                if !entity.subtitle.isEmpty {
                    Text(entity.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            CopyButton(value: entity.label, hint: "Copy \(entity.kind.displayName.lowercased())")
            if entity.degree > 0 {
                Text("\(entity.degree)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("\(entity.degree) links")
            }
            ConfidenceDot(confidence: entity.confidence)
        }
        .padding(.vertical, 3)
    }
}
