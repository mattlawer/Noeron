# Contributing to Noeron

Thanks for helping build Noeron. The most valuable contribution is usually a new
**plugin** — a new OSINT data source — but bug fixes, docs and UI work are equally
welcome.

## Ground rules

- Be respectful — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Contributions are accepted under the project's [MIT license](LICENSE) (inbound = outbound).
- Noeron is for **lawful, authorised** open‑source investigation. Don't contribute
  features whose primary purpose is intrusion, evasion, harassment, or violating a
  data source's terms.

## Getting set up

See [docs/BUILDING.md](docs/BUILDING.md). In short:

```bash
brew install xcodegen
cd Noeron && xcodegen generate && open Noeron.xcodeproj
```

Always re‑run `xcodegen generate` after adding/removing files.

## Workflow

1. Open an issue first for anything non‑trivial (use the templates).
2. Branch from `main`.
3. Make the change; keep it focused. Match the surrounding code's style and comment density.
4. Build clean:
   ```bash
   cd Noeron
   xcodebuild -project Noeron.xcodeproj -scheme Noeron_macOS \
     -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```
5. Update docs (and [docs/OSINT-TOOLS.md](docs/OSINT-TOOLS.md) if you added a source).
6. Open a PR describing **what** and **why**; link the issue.

## Adding a plugin

Read **[docs/PLUGIN-DEVELOPMENT.md](docs/PLUGIN-DEVELOPMENT.md)** and run through its
[checklist](docs/PLUGIN-DEVELOPMENT.md#9-checklist-before-opening-a-pr). The review
focuses on:

- **Correctness** — accurate `acceptedKinds`/`producesKinds`, sane parsing.
- **Noise control** — infra filtering, false‑positive controls, honest confidence,
  attributes vs. nodes used appropriately.
- **Graceful failure** — per‑source errors are non‑fatal.
- **Compliance** — `docURL` links real docs; the source's ToS permits the use.
- **Keyless‑first** — if the source is free, keep it keyless; if it mirrors a paid
  service, wire `freeAlternativeID`.

## Code style

- Swift 5.10, SwiftUI + SwiftData, `SWIFT_STRICT_CONCURRENCY: targeted`.
- Plugins are `Sendable` and must not touch SwiftData or the main actor.
- Prefer small, composable views; keep view bodies type‑checkable (split large ones).
- Comments explain **why**, not what.

## Commit & PR hygiene

- Small, reviewable PRs. One concern per PR.
- Descriptive commit messages.
- No secrets, no personal sample data, no committed `Noeron.xcodeproj`.

## Reporting bugs / security issues

- Bugs: open an issue with repro steps and the relevant **Plugin Log** excerpt.
- Vulnerabilities: follow [SECURITY.md](SECURITY.md) — please don't file public issues for those.
