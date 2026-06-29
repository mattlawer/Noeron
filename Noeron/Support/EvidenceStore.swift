//
//  EvidenceStore.swift
//  Noeron
//
//  Imports evidence files into a managed container directory, hashing them for
//  chain-of-custody integrity. Files live outside the SwiftData store; the model
//  keeps only a relative path + SHA-256.
//

import Foundation
import CryptoKit
import UniformTypeIdentifiers

enum EvidenceStore {
    /// `~/Library/Application Support/Noeron/Evidence`
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Noeron/Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    struct ImportResult {
        let relativePath: String
        let sha256: String
        let byteCount: Int
        let contentType: UTType
        let displayName: String
    }

    /// Copy an external file into the managed store under a fresh UUID name.
    static func importFile(from source: URL) throws -> ImportResult {
        let needsStop = source.startAccessingSecurityScopedResource()
        defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let dest = directory.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)

        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let type = UTType(filenameExtension: ext) ?? .data

        return ImportResult(
            relativePath: filename,
            sha256: hex,
            byteCount: data.count,
            contentType: type,
            displayName: source.lastPathComponent
        )
    }

    /// Persist raw in-memory data (e.g. a fetched image) as evidence.
    static func importData(_ data: Data, suggestedName: String, type: UTType) throws -> ImportResult {
        let ext = type.preferredFilenameExtension ?? "dat"
        let filename = "\(UUID().uuidString).\(ext)"
        let dest = directory.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ImportResult(relativePath: filename, sha256: hex, byteCount: data.count,
                            contentType: type, displayName: suggestedName)
    }

    static func recomputeHash(for item: EvidenceItem) -> String? {
        guard let url = item.fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension Int {
    /// Human readable byte size, e.g. "1.2 MB".
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
