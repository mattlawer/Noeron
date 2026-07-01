//
//  EntityMerge.swift
//  Noeron
//
//  Merge one entity into another (same person/wallet found via different sources):
//  re-points links, unions attributes/timeline, keeps the strongest confidence,
//  then deletes the source. All model mutation on the main actor.
//

import Foundation
import SwiftData

@MainActor
enum EntityMerge {
    /// Merge `source` into `target`, then delete `source`.
    static func merge(_ source: Entity, into target: Entity, in investigation: Investigation, context: ModelContext) {
        guard source.id != target.id else { return }

        // Re-point every edge from the source onto the target.
        for link in source.outgoing { link.source = target }
        for link in source.incoming { link.target = target }

        // Drop self-loops and duplicate edges the re-point may have created.
        var seen = Set<String>()
        for link in target.outgoing + target.incoming {
            guard let s = link.source?.id, let t = link.target?.id, s != t else {
                context.delete(link); continue
            }
            let key = "\(link.kindRaw)|\(s)->\(t)"
            if seen.contains(key) { context.delete(link) } else { seen.insert(key) }
        }

        // Union attributes (keep the target's value on conflicts).
        let existing = Set(target.attributes.map { $0.key })
        for a in source.attributes where !existing.contains(a.key) {
            target.setAttribute(a.key, a.value, kind: a.kind, source: a.source)
        }

        // Keep the strongest signal / flags, and fill an empty subtitle.
        target.confidence = max(target.confidence, source.confidence)
        target.pinned = target.pinned || source.pinned
        target.isSeed = target.isSeed || source.isSeed
        if target.subtitle.isEmpty { target.subtitle = source.subtitle }

        // Re-parent the source's timeline events.
        for e in investigation.eventsArray where e.entity?.id == source.id { e.entity = target }

        target.updatedAt = Date()
        context.delete(source)
        try? context.save()
    }
}
