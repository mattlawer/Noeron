# Changelog

All notable changes to Noeron are documented here. This project aims to follow
[Semantic Versioning](https://semver.org).

## [1.0.1] - 2026-07-01

### Added
- **Graph search & filters**: a search-to-focus field (centres and highlights
  matches), a min-confidence slider, and a tappable kind legend with per-kind
  counts to hide/show node kinds — essential once a graph passes ~50 nodes.
- **Undo for discard**: discarding an entity now shows a brief "Undo" toast that
  restores it (auto-dismisses after a few seconds).
- **First-run onboarding**: a dismissible "Getting started" hint on the Overview
  explaining paste-a-selector → Discover (persisted once dismissed).
- **Selected-subgraph report export**: scope a report to chosen entities; links
  and timeline events are induced by the included set. Reports embed confidence
  (text meter / HTML bar / PDF meter) and discard state (flagged, dimmed).
- Discovery **cancel/stop**, real per-host **rate limiting**, **sticky discards**
  (reversible, not re-discovered), and manual **entity merge**.

### Changed
- macOS report export now opens a native **Save panel** (write to disk) instead
  of the share sheet; iOS keeps the share sheet.
- Default discovery depth 2 / entity cap 50; clearer Google Dork match context.

### Fixed
- Graph selection inspector no longer clips or drifts off-screen at some window
  sizes — it's now a bounded, centred floating card anchored to the viewport.
- Selector type menu and multi-selector entity-cap expansion.

## [1.0.0] - 2026-06-29

### Added
- On-chain plugins (keyless): Bitcoin, Ethereum and Solana — balance, USD estimate,
  held tokens, first/last activity and the last 25 transactions with explorer links.
- Per-plugin **detail view** with editable parameters (e.g. custom RPC endpoints)
  and API credentials; non-secret parameters stored via `PluginParameters`.
- Unit test target (`NoeronTests`) and UI test target (`NoeronUITests`) that drive
  an offline demo mode and capture the README screenshots.
- README screenshots generated from the offline demo (`scripts/screenshots.sh`).
- Full documentation set under `docs/` (architecture, data model, discovery
  engine, plugin development, building, OSINT tool map, open‑source plan).
- Professional `README.md`; open‑source governance files (`LICENSE` (MIT),
  `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`), GitHub issue/PR
  templates, `.gitignore`.
- Keyless email plugins: Email Intelligence, Gravatar, GitHub‑by‑email, Account
  Existence, EmailRep.
- Phone Intelligence and a single data‑driven Username Sweep (~40 sites).
- Recon plugins ported from classic tools: Subdomain Enumeration, Wayback,
  Typosquat, Reverse IP/PTR, urlscan.io, Geocoding.
- Company Registry (keyless French gov API + registry record links).
- Google Dorks plugin (SerpAPI / Google Custom Search).
- Free alternatives to paid services, on by default: XposedOrNot (↔ HIBP) and
  Shodan InternetDB (↔ Shodan); `freeAlternativeID` surfaced in the UI.
- Copy‑to‑clipboard buttons on entities and facts.
- Tabbed Settings (Plugins / Discovery / About).
- Live auto‑expand progress (per‑step log) on every screen that can run discovery.

### Changed
- Infrastructure/free‑webmail filtering so provider domains (Google, Cloudflare,
  consumer ISPs like `orange.fr`) don't explode the graph.
- Timeline events and username nodes are de‑duplicated; one‑time cleanup of
  pre‑existing duplicate events on open.
- `KeychainStore` reads a non‑secret index for UI checks, so browsing never
  triggers a macOS Keychain prompt.

> Catalogue: 39 plugins (~27 keyless, on by default).
