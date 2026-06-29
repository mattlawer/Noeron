---
name: New plugin proposal
about: Propose a new OSINT data source as a Noeron plugin
title: "plugin: <source name>"
labels: ["plugin", "enhancement"]
---

## Source
- **Name / URL:**
- **Docs (`docURL`):**
- **Auth:** keyless / API key / OAuth (which?)
- **Terms of service:** link — does it permit programmatic use?

## What it returns
- **Accepts (input kinds):** e.g. `.email`, `.domain`
- **Produces (output kinds/links):** e.g. `.breach` via `.appearsIn`
- **Sample response (trimmed):**
```json
```

## Notes
- Free alternative to a paid service? If so, which (`freeAlternativeID`)?
- Rate limits / quota?
- Any noise concerns (infra hostnames, soft‑404s, false positives)?

> Before implementing, read `docs/PLUGIN-DEVELOPMENT.md`.
