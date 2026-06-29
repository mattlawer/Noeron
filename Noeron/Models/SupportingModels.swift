//
//  SupportingModels.swift
//  Noeron
//
//  Notes, evidence (file-backed, chain-of-custody), timeline events, tags,
//  and the plugin-run audit log.
//

import Foundation
import SwiftData

// MARK: - Notes

@Model
final class NoteItem {
    var id: UUID = UUID()
    var title: String = "Note"
    /// Markdown body.
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pinned: Bool = false

    var investigation: Investigation?
    /// Optional entity this note annotates (inverse declared on `Entity.notes`).
    var entity: Entity?

    init(title: String = "Note", body: String = "", entity: Entity? = nil) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.entity = entity
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Evidence (file-backed)

@Model
final class EvidenceItem {
    var id: UUID = UUID()
    var displayName: String = ""
    /// Path relative to the app's Evidence container directory.
    var relativePath: String = ""
    var contentTypeIdentifier: String = "public.data"   // UTType identifier
    var byteCount: Int = 0
    /// SHA-256 hex digest captured at import time (integrity / chain of custody).
    var sha256: String = ""
    var capturedAt: Date = Date()
    var addedAt: Date = Date()
    var addedBy: String = ""
    var sourceURLString: String = ""
    var notes: String = ""
    /// Small JPEG/PNG thumbnail for fast list rendering.
    @Attribute(.externalStorage) var thumbnailData: Data?

    var investigation: Investigation?
    /// Inverse of `Entity.evidence` (one-to-one); set when surfaced as a graph node.
    var sourceEntity: Entity?

    init(displayName: String,
         relativePath: String,
         contentTypeIdentifier: String = "public.data",
         byteCount: Int = 0,
         sha256: String = "",
         sourceURL: String = "",
         addedBy: String = "") {
        self.id = UUID()
        self.displayName = displayName
        self.relativePath = relativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.sha256 = sha256
        self.sourceURLString = sourceURL
        self.addedBy = addedBy
        self.capturedAt = Date()
        self.addedAt = Date()
    }
}

extension EvidenceItem {
    /// Resolved on-disk URL inside the app's Evidence directory.
    var fileURL: URL? {
        guard !relativePath.isEmpty else { return nil }
        return EvidenceStore.directory.appendingPathComponent(relativePath)
    }
}

// MARK: - Timeline

@Model
final class TimelineEvent {
    enum Precision: String, Codable, Sendable { case exact, day, month, year }

    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var date: Date = Date()
    var precisionRaw: String = Precision.day.rawValue
    /// Short category label e.g. "Domain", "Breach", "Account".
    var category: String = ""
    var confidence: Double = 1.0
    var sourcePlugin: String = ""

    var investigation: Investigation?
    /// Inverse declared on `Entity.events`.
    var entity: Entity?

    init(title: String,
         date: Date,
         precision: Precision = .day,
         detail: String = "",
         category: String = "",
         confidence: Double = 1.0,
         sourcePlugin: String = "",
         entity: Entity? = nil) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.precisionRaw = precision.rawValue
        self.detail = detail
        self.category = category
        self.confidence = confidence
        self.sourcePlugin = sourcePlugin
        self.entity = entity
    }
}

extension TimelineEvent {
    var precision: Precision {
        get { Precision(rawValue: precisionRaw) ?? .day }
        set { precisionRaw = newValue.rawValue }
    }
    var displayDate: String {
        let f = DateFormatter()
        switch precision {
        case .exact: f.dateFormat = "yyyy-MM-dd HH:mm"
        case .day:   f.dateFormat = "yyyy-MM-dd"
        case .month: f.dateFormat = "yyyy-MM"
        case .year:  f.dateFormat = "yyyy"
        }
        return f.string(from: date)
    }
    var year: Int { Calendar.current.component(.year, from: date) }
}

// MARK: - Tags

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8B949E"
    var investigation: Investigation?

    init(name: String, colorHex: String = "#8B949E") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - Plugin run audit log

@Model
final class PluginRun {
    enum Status: String, Codable, Sendable { case success, empty, failed, running }

    var id: UUID = UUID()
    var pluginID: String = ""
    var pluginName: String = ""
    var targetLabel: String = ""
    var targetKindRaw: String = ""
    var startedAt: Date = Date()
    var finishedAt: Date?
    var statusRaw: String = Status.running.rawValue
    var discoveredEntities: Int = 0
    var discoveredLinks: Int = 0
    var message: String = ""
    /// First ~4 KB of the raw API response, retained for evidentiary review.
    var rawExcerpt: String = ""

    var investigation: Investigation?

    init(pluginID: String, pluginName: String, targetLabel: String, targetKind: EntityKind) {
        self.id = UUID()
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.targetLabel = targetLabel
        self.targetKindRaw = targetKind.rawValue
        self.startedAt = Date()
    }
}

extension PluginRun {
    var status: Status {
        get { Status(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }
    var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}
