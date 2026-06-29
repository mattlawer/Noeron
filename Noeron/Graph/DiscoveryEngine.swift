//
//  DiscoveryEngine.swift
//  Noeron
//
//  The killer feature: automatic graph expansion. Given a seed entity it runs the
//  enabled plugins concurrently, merges their structured findings into the SwiftData
//  graph (de-duplicating nodes and edges), then breadth-first expands the new nodes
//  up to a depth limit — turning one selector into a whole picture.
//
//  Threading model: the engine is @MainActor and performs *all* model mutation on the
//  main actor. Plugins receive only Sendable snapshots and run off the main actor in a
//  task group, so the UI stays responsive while lookups are in flight.
//

import Foundation
import SwiftData

/// Sendable result of one plugin invocation, returned from the task group.
struct PluginRunOutcome: Sendable {
    let pluginID: String
    let pluginName: String
    let result: PluginResult?
    let errorMessage: String?
    let duration: TimeInterval
}

@MainActor
final class DiscoveryEngine: ObservableObject {
    @Published var isRunning = false
    @Published var statusText = ""
    @Published var processed = 0
    @Published var discovered = 0
    @Published var liveLog: [LogLine] = []
    @Published var lastError: String?

    /// Tunable scope guards (exposed in Settings).
    @Published var maxDepth = 2
    @Published var maxEntities = 50

    struct LogLine: Identifiable { let id = UUID(); let text: String; let isError: Bool; let date = Date() }

    private let registry: PluginRegistry
    private let context: PluginContext

    init(registry: PluginRegistry? = nil, context: PluginContext = PluginContext()) {
        self.registry = registry ?? .shared
        self.context = context
    }

    // MARK: - Public API

    /// Breadth-first automatic expansion from a single seed entity.
    func expand(seed: Entity,
                in investigation: Investigation,
                modelContext: ModelContext,
                maxDepth overrideDepth: Int? = nil) async {
        await expand(seeds: [seed], in: investigation, modelContext: modelContext, maxDepth: overrideDepth)
    }

    /// Breadth-first automatic expansion from one or more seed entities at once.
    /// All seeds share a single run, index and visited-set, so cross-seed findings
    /// de-duplicate and converge into one graph (the headline feature).
    func expand(seeds: [Entity],
                in investigation: Investigation,
                modelContext: ModelContext,
                maxDepth overrideDepth: Int? = nil) async {
        guard !isRunning, !seeds.isEmpty else { return }
        beginRun(label: seeds.count == 1 ? seeds[0].label : "\(seeds.count) selectors")
        defer { endRun() }

        let depthLimit = overrideDepth ?? maxDepth
        var index = buildIndex(investigation)
        var linkKeys = buildLinkKeys(investigation)
        var eventKeys = buildEventKeys(investigation)
        var visitedPairs = Set<String>()       // "entityID|pluginID"
        var processedEntities = Set<UUID>()
        var queue: [(Entity, Int)] = seeds.map { ($0, 0) }

        while !queue.isEmpty {
            if investigation.entitiesArray.count >= maxEntities {
                log("Reached \(maxEntities)-entity cap; stopping expansion.", error: false)
                break
            }
            let (entity, depth) = queue.removeFirst()
            guard processedEntities.insert(entity.id).inserted else { continue }

            let snapshot = EntitySnapshot(entity)
            let plugins = registry
                .discoveryPlugins(for: snapshot, context: context)
                .filter { !visitedPairs.contains("\(entity.id)|\($0.id)") }
            guard !plugins.isEmpty else { continue }

            statusText = "Expanding “\(entity.label)” · depth \(depth) · \(plugins.count) plugin(s)"
            processed += 1

            let outcomes = await runConcurrently(plugins: plugins, snapshot: snapshot)

            for outcome in outcomes {
                visitedPairs.insert("\(entity.id)|\(outcome.pluginID)")
                logRun(outcome, on: entity, in: investigation, modelContext: modelContext)

                guard let result = outcome.result else { continue }
                let created = apply(result,
                                    pluginID: outcome.pluginID,
                                    pluginName: outcome.pluginName,
                                    to: entity,
                                    in: investigation,
                                    modelContext: modelContext,
                                    index: &index,
                                    linkKeys: &linkKeys,
                                    eventKeys: &eventKeys)
                if !created.isEmpty {
                    discovered += created.count
                    log("\(outcome.pluginName): +\(created.count) on \(entity.label)", error: false)
                }
                if depth < depthLimit {
                    for node in created { queue.append((node, depth + 1)) }
                }
            }
            try? modelContext.save()
        }

        investigation.touch()
        try? modelContext.save()
        statusText = "Done · \(discovered) discovered"
    }

    /// Run every enabled, applicable plugin on a single entity (one hop, no recursion).
    func discoverOneHop(on entity: Entity, in investigation: Investigation, modelContext: ModelContext) async {
        await expand(seed: entity, in: investigation, modelContext: modelContext, maxDepth: 0)
    }

    /// Run one specific plugin on demand (used by the entity inspector). Bypasses the
    /// enabled-set so analysts can preview any adapter, including sample stubs.
    func runSingle(plugin: any Plugin, on entity: Entity, in investigation: Investigation, modelContext: ModelContext) async {
        guard !isRunning else { return }
        beginRun(label: entity.label)
        defer { endRun() }

        var index = buildIndex(investigation)
        var linkKeys = buildLinkKeys(investigation)
        var eventKeys = buildEventKeys(investigation)
        let snapshot = EntitySnapshot(entity)
        statusText = "Running \(plugin.metadata.name) on \(entity.label)"

        let outcomes = await runConcurrently(plugins: [plugin], snapshot: snapshot)
        for outcome in outcomes {
            logRun(outcome, on: entity, in: investigation, modelContext: modelContext)
            guard let result = outcome.result else {
                if let e = outcome.errorMessage { lastError = e }
                continue
            }
            let created = apply(result, pluginID: outcome.pluginID, pluginName: outcome.pluginName,
                                to: entity, in: investigation, modelContext: modelContext,
                                index: &index, linkKeys: &linkKeys, eventKeys: &eventKeys)
            discovered += created.count
            log("\(outcome.pluginName): +\(created.count)", error: false)
        }
        investigation.touch()
        try? modelContext.save()
    }

    // MARK: - Concurrent plugin execution (off the main actor)

    private func runConcurrently(plugins: [any Plugin], snapshot: EntitySnapshot) async -> [PluginRunOutcome] {
        let ctx = context
        return await withTaskGroup(of: PluginRunOutcome.self) { group in
            for plugin in plugins {
                let meta = plugin.metadata
                group.addTask {
                    let start = Date()
                    do {
                        let result = try await plugin.run(on: snapshot, context: ctx)
                        return PluginRunOutcome(pluginID: meta.id, pluginName: meta.name,
                                                result: result, errorMessage: nil,
                                                duration: Date().timeIntervalSince(start))
                    } catch {
                        let message = (error as? PluginError)?.errorDescription ?? error.localizedDescription
                        return PluginRunOutcome(pluginID: meta.id, pluginName: meta.name,
                                                result: nil, errorMessage: message,
                                                duration: Date().timeIntervalSince(start))
                    }
                }
            }
            var collected: [PluginRunOutcome] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }
    }

    // MARK: - Applying results to the graph (main actor)

    @discardableResult
    private func apply(_ result: PluginResult,
                       pluginID: String,
                       pluginName: String,
                       to input: Entity,
                       in investigation: Investigation,
                       modelContext: ModelContext,
                       index: inout [String: Entity],
                       linkKeys: inout Set<String>,
                       eventKeys: inout Set<String>) -> [Entity] {

        // 1. Facts onto the input node.
        for attr in result.inputAttributes {
            input.setAttribute(attr.key, attr.value, kind: attr.kind,
                               source: attr.source.isEmpty ? pluginName : attr.source)
        }

        // 2. Discovered nodes (+ edges back to the input).
        var created: [Entity] = []
        for discovery in result.entities {
            let label = Normalizer.label(for: discovery.kind, discovery.label)
            guard !label.isEmpty else { continue }
            let key = "\(discovery.kind.rawValue)|\(label.lowercased())"

            let node: Entity
            if let existing = index[key] {
                node = existing
                node.confidence = max(node.confidence, discovery.confidence)
            } else {
                let fresh = Entity(kind: discovery.kind, label: label, subtitle: discovery.subtitle,
                                   confidence: discovery.confidence, sourcePlugin: pluginName,
                                   sourceURL: discovery.sourceURL)
                positionNear(fresh, input)
                modelContext.insert(fresh)
                fresh.investigation = investigation
                index[key] = fresh
                created.append(fresh)
                node = fresh
            }

            for attr in discovery.attributes {
                node.setAttribute(attr.key, attr.value, kind: attr.kind,
                                  source: attr.source.isEmpty ? pluginName : attr.source)
            }
            if result.sample {
                node.setAttribute("Provenance",
                                  "Sample data — configure \(pluginName) API key for live results",
                                  source: pluginName)
            }

            let (from, to) = discovery.linkDirection == .fromInput ? (input, node) : (node, input)
            makeLink(discovery.linkKind, from: from, to: to, confidence: discovery.confidence,
                     plugin: pluginName, in: investigation, modelContext: modelContext, linkKeys: &linkKeys)
        }

        // 3. Timeline events (de-duplicated: the same dated fact reached via several
        // paths or re-runs must not stack up — see the repeated "account created" bug).
        for event in result.events {
            let key = Self.eventKey(title: event.title, date: event.date,
                                    precision: event.precision, category: event.category)
            guard eventKeys.insert(key).inserted else { continue }
            let te = TimelineEvent(title: event.title, date: event.date, precision: event.precision,
                                   detail: event.detail, category: event.category,
                                   sourcePlugin: pluginName, entity: input)
            modelContext.insert(te)
            te.investigation = investigation
        }

        return created
    }

    private func makeLink(_ kind: LinkKind, from: Entity, to: Entity, confidence: Double,
                          plugin: String, in investigation: Investigation,
                          modelContext: ModelContext, linkKeys: inout Set<String>) {
        guard from.id != to.id else { return }
        let key = "\(kind.rawValue)|\(from.id)->\(to.id)"
        let reverse = "\(kind.rawValue)|\(to.id)->\(from.id)"
        guard !linkKeys.contains(key), !linkKeys.contains(reverse) else { return }
        let link = EntityLink(kind: kind, source: from, target: to, confidence: confidence, sourcePlugin: plugin)
        modelContext.insert(link)
        link.investigation = investigation
        linkKeys.insert(key)
    }

    // MARK: - Indices & geometry

    private func buildIndex(_ investigation: Investigation) -> [String: Entity] {
        Dictionary(investigation.entitiesArray.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func buildLinkKeys(_ investigation: Investigation) -> Set<String> {
        Set(investigation.linksArray.compactMap { link in
            guard let s = link.source?.id, let t = link.target?.id else { return nil }
            return "\(link.kindRaw)|\(s)->\(t)"
        })
    }

    private func buildEventKeys(_ investigation: Investigation) -> Set<String> {
        Set(investigation.eventsArray.map {
            DiscoveryEngine.eventKey(title: $0.title, date: $0.date, precision: $0.precision, category: $0.category)
        })
    }

    /// One-time cleanup: remove duplicate timeline events already persisted in an
    /// investigation (from before dedup existed). Idempotent — safe to call on every
    /// open; it deletes only when duplicates of the same fact exist, keeping the
    /// earliest-created one. Returns how many were removed.
    @discardableResult
    static func dedupeTimeline(_ investigation: Investigation, modelContext: ModelContext) -> Int {
        var seen = Set<String>()
        var removed = 0
        // Keep the first occurrence of each identity; order by date for determinism.
        let ordered = (investigation.events ?? []).sorted { $0.date < $1.date }
        for event in ordered {
            let key = eventKey(title: event.title, date: event.date, precision: event.precision, category: event.category)
            if seen.insert(key).inserted { continue }
            modelContext.delete(event)
            removed += 1
        }
        if removed > 0 { try? modelContext.save() }
        return removed
    }

    /// Identity for a timeline event: same title + category + date (at the event's
    /// own precision) is the same fact, regardless of which plugin/path produced it.
    static func eventKey(title: String, date: Date, precision: TimelineEvent.Precision, category: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        switch precision {
        case .exact: f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        case .day:   f.dateFormat = "yyyy-MM-dd"
        case .month: f.dateFormat = "yyyy-MM"
        case .year:  f.dateFormat = "yyyy"
        }
        return "\(category.lowercased())|\(f.string(from: date))|\(title.lowercased())"
    }

    /// Drop new nodes in a ring around their parent so the canvas isn't a pile at origin.
    private func positionNear(_ node: Entity, _ parent: Entity) {
        let angle = Double.random(in: 0..<(2 * .pi))
        let radius = Double.random(in: 90...170)
        node.canvasX = parent.canvasX + cos(angle) * radius
        node.canvasY = parent.canvasY + sin(angle) * radius
    }

    // MARK: - Audit log

    private func logRun(_ outcome: PluginRunOutcome, on entity: Entity,
                        in investigation: Investigation, modelContext: ModelContext) {
        let run = PluginRun(pluginID: outcome.pluginID, pluginName: outcome.pluginName,
                            targetLabel: entity.label, targetKind: entity.kind)
        run.finishedAt = Date()
        run.investigation = investigation
        if let error = outcome.errorMessage {
            run.status = .failed
            run.message = error
            log("\(outcome.pluginName) failed: \(error)", error: true)
        } else if let result = outcome.result {
            run.status = result.isEmpty ? .empty : .success
            run.discoveredEntities = result.entities.count
            run.discoveredLinks = result.entities.count
            run.message = result.sample ? "Sample data (no live API key configured)" : ""
            run.rawExcerpt = result.rawExcerpt
        }
        modelContext.insert(run)
    }

    private func beginRun(label: String) {
        isRunning = true; lastError = nil; processed = 0; discovered = 0
        liveLog = [LogLine(text: "Starting discovery from “\(label)”…", isError: false)]
    }
    private func endRun() { isRunning = false }
    private func log(_ text: String, error: Bool) {
        liveLog.append(LogLine(text: text, isError: error))
        if liveLog.count > 200 { liveLog.removeFirst(liveLog.count - 200) }
        if error { lastError = text }
    }
}
