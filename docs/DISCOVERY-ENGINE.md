# Discovery engine

`Graph/DiscoveryEngine.swift` is the headline feature: given one or more seed
entities it runs the enabled plugins, merges their findings into the graph, and
**breadth‑first expands** the new nodes until it hits a depth or entity limit.

## Public API

```swift
@MainActor final class DiscoveryEngine: ObservableObject {
    func expand(seed: Entity,  in: Investigation, modelContext:, maxDepth:) async
    func expand(seeds: [Entity], in: Investigation, modelContext:, maxDepth:) async
    func discoverOneHop(on: Entity, in: Investigation, modelContext:) async   // maxDepth 0
    func runSingle(plugin:, on: Entity, in: Investigation, modelContext:) async
}
```

Observable state drives the UI: `isRunning`, `statusText`, `processed`,
`discovered`, `liveLog` (the per‑step log shown by `DiscoveryProgressView`),
`lastError`, plus the tunables `maxDepth` and `maxEntities`.

## The algorithm

```
queue ← [(seed, 0) for each seed]
index, linkKeys, eventKeys ← snapshot of existing graph (for de-dup)
while queue not empty and entityCount < maxEntities:
    (entity, depth) ← queue.removeFirst()
    if already processed: continue
    plugins ← registry.discoveryPlugins(for: snapshot)   # enabled ∧ applicable ∧ credentials present
            minus already-run (entity,plugin) pairs
    outcomes ← run all plugins CONCURRENTLY, off the main actor
    for outcome in outcomes:
        created ← apply(outcome.result)   # merge nodes/links/events with de-dup + provenance
        if depth < depthLimit: queue.append((node, depth+1)) for node in created
    save()
```

- **Single shared run** for multiple seeds: `expand(seeds:)` seeds the queue with
  all of them so cross‑seed findings converge and de‑duplicate into one graph.
  `expand(seed:)` is a one‑element convenience wrapper.
- **`visitedPairs`** (`entityID|pluginID`) ensures a plugin runs at most once per
  entity per run.
- **Scope guards**: `maxDepth` (1–4) and `maxEntities` (50–1000), both in Settings.

## Concurrency & threading

- The engine is `@MainActor`; **all** SwiftData mutation happens on the main actor.
- For each entity, applicable plugins run inside a `withTaskGroup` **off** the main
  actor. Each task gets an immutable `EntitySnapshot` and the shared `PluginContext`.
- A plugin that throws is captured as a failed `PluginRunOutcome` (logged, never
  fatal); a successful one returns a `PluginResult` that the engine applies on the
  main actor.

## Merge & de‑duplication (`apply`)

1. **Input attributes** are written onto the source entity (provenance preserved).
2. **Discovered entities** are looked up by `kind | normalized(label)`; an existing
   node is reused (confidence merged upward), otherwise a fresh node is created,
   positioned near its parent, and linked. Edges are de‑duplicated by
   `kind | from -> to` (reverse‑aware).
3. **Timeline events** are de‑duplicated by `category | date@precision | title`
   (`eventKey`), so the same dated fact never stacks up.
4. A **`PluginRun`** audit record is written for every plugin invocation.

`dedupeTimeline(_:modelContext:)` is an idempotent one‑time cleanup that removes
duplicate events persisted before event de‑dup existed; `ContentView` calls it the
first time each investigation is opened.

## Noise control

Before a hostname becomes a node, network plugins consult
`InfraFilter.isInfrastructure(_:)` (providers/CDNs/mail/DNS hosts) and
`InfraFilter.isFreeWebmail(_:)` (consumer webmail/ISP domains). This stops, for
example, an `@gmail.com` or `@orange.fr` address from expanding the provider's
entire infrastructure. The `Username Sweep` plugin additionally runs a
**negative‑control** check (a sentinel username) to discard sites whose detector
returns a match for everyone. See the relevant plugin sources and
[PLUGIN-DEVELOPMENT.md](PLUGIN-DEVELOPMENT.md#avoiding-noise).
