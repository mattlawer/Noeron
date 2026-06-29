# Data model

Noeron stores an investigation as a graph in **SwiftData**. The schema is
deliberately flat and CloudKit‑friendly: every property has a default, every
relationship is optional with an inverse, and there are no `.unique` constraints.

## Core types (`Models/`)

### `EntityKind` (`EntityKind.swift`)
An enum of every node type: `person`, `company`, `organization`, `email`, `phone`,
`username`, `socialProfile`, `domain`, `subdomain`, `url`, `ipAddress`, `asn`,
`certificate`, `cryptoWallet`, `vehicle`, `location`, `breach`, `image`,
`document`, `note`. Each kind carries its display name, plural, SF Symbol, accent
colour and sidebar section. Foundation‑only, so it is shared across model, plugin
and report layers.

### `Entity` (`Entity.swift`)
The unified node. Instead of many polymorphic classes, every node is an `Entity`
tagged with an `EntityKind`. Key fields:

| Field | Meaning |
|---|---|
| `kindRaw` / `kind` | the `EntityKind` (stored as its raw string) |
| `label` | primary display value (`john@example.com`, `ACME Ltd`) |
| `subtitle` | secondary line (role, country, normalised form) |
| `confidence` | 0…1, used for styling and report flags |
| `attributesData` / `attributes` | JSON‑encoded `[EntityAttribute]` — the typed fact bag |
| `sourcePlugin` / `sourceURLString` | provenance |
| `outgoingLinks` / `incomingLinks` | `EntityLink` relationships |
| `evidence` | optional `EvidenceItem` for file‑backed kinds |
| `pinned` / `isSeed` / `canvasX/Y` | UI state persisted with the node |

### `EntityAttribute` (value type, in `Entity.swift`)
One typed key/value fact: `key`, `value`, `kind` (`text/number/date/url/boolean`),
and `source` (the plugin that contributed it — provenance for reports). URL‑kind
attributes render as clickable links in the inspector.

### `EntityLink` (`EntityLink.swift`)
A directed, typed edge. `LinkKind` is the semantic label:
`resolvesTo`, `hostedOn`, `registeredBy`, `ownedBy`, `employs`, `memberOf`,
`hasEmail`, `hasPhone`, `hasUsername`, `hasProfile`, `controls`, `issuedFor`,
`subdomainOf`, `partOf`, `appearsIn`, `mentions`, `relatedTo`.
(Named `EntityLink`, not `Relationship`, to avoid colliding with SwiftData's macro.)

### `Investigation` (`Investigation.swift`)
The workspace root: title, case number, classification, colour, timestamps, and
the collections (`entities`, `links`, `events`, `notes`, `evidence`, `tags`,
`pluginRuns`) plus convenience accessors (`entitiesArray`, `populatedKinds`,
`count(of:)`, …).

### `SupportingModels.swift`
- `TimelineEvent` — a dated fact: `title`, `date`, `precision` (`exact/day/month/year`),
  `category`, `detail`, `confidence`, `sourcePlugin`, optional `entity`.
- `Note` — free text attached to an entity or investigation.
- `EvidenceItem` — an imported file: managed copy + SHA‑256 hash for chain of custody.
- `Tag` — labelling.
- `PluginRun` — the audit log: which plugin ran on what, status, counts, raw excerpt.

### `ModelSchema.swift`
Declares the schema and builds the `ModelContainer`. It checks the iCloud
entitlement at runtime before requesting CloudKit (a CloudKit call without the
entitlement is a hard crash), so an unsigned/local build runs on a local store and
never touches CloudKit.

## How plugins see the graph

Plugins do **not** use these model types directly. They receive an immutable,
`Sendable` `EntitySnapshot` (`id`, `kind`, `label`, `subtitle`, `attributes`) and
return a `PluginResult` of plain value types (`DiscoveredEntity`, `DiscoveredEvent`,
`EntityAttribute`). The `DiscoveryEngine` is the only code that turns those values
into `Entity` / `EntityLink` / `TimelineEvent` rows. This boundary is what keeps
plugins off the main actor and unit‑testable. See [PLUGIN-DEVELOPMENT.md](PLUGIN-DEVELOPMENT.md).

## De‑duplication keys

- **Entities**: `kind | normalized(label).lowercased()` (via `Normalizer`).
- **Links**: `kind | source.id -> target.id` (undirected‑aware).
- **Events**: `category | date@precision | title` (see `DiscoveryEngine.eventKey`).

These keys are why re‑running discovery, or reaching a node by several paths, does
not create duplicate nodes, edges or timeline entries.
