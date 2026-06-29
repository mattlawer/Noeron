# Architecture

Noeron is a single SwiftUI app target that runs natively on macOS, iPadOS and iOS.
There is no server: everything happens on device, and plugins talk directly to
public data sources over HTTPS.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Views (SwiftUI)                                              │
│   ContentView · WorkspaceNavigator · Graph · Timeline ·      │
│   EntityDetailView (inspector) · SettingsView · Reports      │
└───────────────▲───────────────────────────────▲─────────────┘
                │ observes (@Published)          │ reads/writes
┌───────────────┴───────────────┐   ┌────────────┴─────────────┐
│ DiscoveryEngine (@MainActor)   │   │ SwiftData ModelContext   │
│   BFS expansion · merge · log  │   │   Investigation graph    │
└───────────────▲────────────────┘   └──────────────────────────┘
                │ runs (off main actor, concurrently)
┌───────────────┴───────────────────────────────────────────────┐
│ Plugins (Sendable)                                            │
│   PluginRegistry → [any Plugin] → run(on: EntitySnapshot)     │
│   Live/ (real network)   Stub/ (key-based + public)           │
└───────────────▲───────────────────────────────────────────────┘
                │ uses
┌───────────────┴───────────────┐   ┌──────────────────────────┐
│ Intelligence                   │   │ Support                  │
│   EntityExtractor · Normalizer │   │ Keychain · Evidence · …  │
└────────────────────────────────┘   └──────────────────────────┘
```

## Subsystems

### `NoeronApp.swift`
`@main`. Builds the `ModelContainer` (local, or CloudKit‑backed when the iCloud
entitlement is present), injects `AppState`, `PluginRegistry.shared` and a
`DiscoveryEngine` into the environment, defines the main `WindowGroup`, the
`Settings` scene, and menu commands, and routes Spotlight/App‑Intent deep links.

### `Models/` — the graph
SwiftData `@Model` classes. A single `Entity` tagged with an `EntityKind` is every
node; `EntityLink` is a directed, typed edge; `Investigation` is the workspace
root; `SupportingModels` holds `TimelineEvent`, `Note`, `EvidenceItem`, `Tag`,
`PluginRun`. Kind‑specific facts live in a JSON‑encoded `[EntityAttribute]` bag so
the schema stays flat and CloudKit‑friendly. Full detail: [DATA-MODEL.md](DATA-MODEL.md).

### `Plugins/` — the data sources
- `PluginCore.swift` — the `Plugin` protocol and the `Sendable` value types that
  cross the actor boundary (`EntitySnapshot`, `DiscoveredEntity`, `PluginResult`,
  `PluginMetadata`, `PluginContext` with its networking helpers).
- `PluginRegistry.swift` — the catalogue (`defaultCatalogue`), the enabled set
  (persisted to `UserDefaults`), and lookup/grouping helpers.
- **One file per plugin**, grouped by folder:
  - `Live/` — keyless plugins that make real network calls (most of the app), plus
    `InfraFilter.swift`, the provider/CDN/webmail deny‑list that suppresses
    infrastructure noise.
  - `Public/` — keyless public‑source plugins (Wikidata, SEC EDGAR, Reddit,
    Mastodon, Bluesky).
  - `KeyBased/` — services that require an API key (Shodan, Censys, Hunter, HIBP,
    Intelligence X, VirusTotal, OpenCorporates, Companies House, LinkedIn,
    Telegram, Historical DNS).
  - `Shared/PluginHelpers.swift` — small helpers shared across plugins (tolerant
    date parsing, URL/credential string helpers, defensive JSON decode).

Plugins never touch SwiftData. They receive an immutable `EntitySnapshot` and
return a `PluginResult`; the engine writes the result into the store. This is what
lets them run off the main actor and stay easily testable.

### `Graph/` — discovery & layout
- `DiscoveryEngine.swift` — `@MainActor` orchestrator. Runs plugins concurrently
  off the main actor, merges results (with node/edge/event de‑duplication and
  provenance), and breadth‑first expands new nodes. See [DISCOVERY-ENGINE.md](DISCOVERY-ENGINE.md).
- `GraphLayout.swift` — force‑directed (Fruchterman–Reingold) layout for the canvas.

### `Intelligence/`
- `EntityExtractor.swift` — regex detection of emails, URLs, domains, IPs, wallets,
  phones and `@handles` from free text; plus `classifySingle` for a single token.
- `Normalizer.swift` — canonical labels per kind so the graph de‑duplicates
  reliably (e.g. `@handle`→`handle`, `WWW.Example.com.`→`example.com`).

### `Views/`
SwiftUI throughout. `ContentView` is the three‑column split view; the workspace is
sectioned by `WorkspaceNavigator`; `EntityDetailView` is the inspector that runs
plugins on demand and shows live discovery progress; `SettingsView` is the tabbed
Plugins/Discovery/About panel.

### OS integrations
- `Spotlight/` — indexes entities & investigations; results deep‑link in.
- `Intents/` — App Intents / Shortcuts ("Add a selector", "Start an investigation").
- `QuickLook/` — in‑app evidence previews.
- `Reports/` — Markdown, HTML (inline SVG graph) and PDF export.

### `Support/`
`AppState` (navigation), `KeychainStore` (API keys — see its header for why the UI
never reads the Keychain during browsing), `EvidenceStore` (file import + SHA‑256
hashing for chain of custody), `Theme`, `IntentRouter`.

## End‑to‑end data flow

1. User pastes/type selectors in **Overview** (or taps **Auto‑expand** in the inspector).
2. `EntityExtractor`/typed rows produce seed entities; `Normalizer` canonicalises labels.
3. `DiscoveryEngine.expand(seeds:)` snapshots each entity and asks `PluginRegistry`
   for enabled, applicable plugins.
4. Plugins run concurrently off the main actor and return `PluginResult`s.
5. The engine merges results into the `Investigation` graph (dedup + provenance),
   emits `TimelineEvent`s, logs a `PluginRun`, and queues new nodes.
6. Views observe the `@Published` engine state and the SwiftData store and update live.
7. The investigation can be exported via `Reports/`.

## Concurrency model

- `DiscoveryEngine` is `@MainActor`; **all** SwiftData mutation happens on the main actor.
- Plugins are `Sendable` and run inside a `TaskGroup` **off** the main actor, given
  only a `Sendable` `EntitySnapshot` and a shared `PluginContext`.
- The project builds with `SWIFT_STRICT_CONCURRENCY: targeted`.
