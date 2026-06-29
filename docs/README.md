# Noeron documentation

Start here. These documents describe every part of the software.

## For users
- [BUILDING.md](BUILDING.md) — build, sign, enable iCloud, troubleshoot.
- [OSINT-TOOLS.md](OSINT-TOOLS.md) — which well‑known OSINT tool each plugin covers (keyless vs. key).

## For contributors & plugin authors
- [ARCHITECTURE.md](ARCHITECTURE.md) — the subsystems and how data flows through them.
- [DATA-MODEL.md](DATA-MODEL.md) — entities, links, attributes, the SwiftData/CloudKit schema.
- [DISCOVERY-ENGINE.md](DISCOVERY-ENGINE.md) — the automatic graph‑expansion algorithm and threading model.
- [PLUGIN-DEVELOPMENT.md](PLUGIN-DEVELOPMENT.md) — **the plugin authoring guide** (protocol, examples, testing, checklist).
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — workflow, style, review.

## For maintainers
- [OPEN-SOURCE-PLAN.md](OPEN-SOURCE-PLAN.md) — the plan to open‑source Noeron and grow a plugin ecosystem.
- [../SECURITY.md](../SECURITY.md) — vulnerability reporting.

## Reading order
If you want to add a data source, read **ARCHITECTURE → DATA-MODEL → PLUGIN-DEVELOPMENT** in that order. They build on each other and the plugin guide assumes the vocabulary from the first two.
