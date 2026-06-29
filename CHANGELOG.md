# Changelog

All notable changes to Noeron are documented here. This project aims to follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

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
