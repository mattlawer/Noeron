# Open‑source plan

A staged plan to open‑source Noeron and grow a community plugin ecosystem.
The guiding principle: **keyless‑first, plugin‑extensible, lawful by design.**

## Goals

1. Ship a trustworthy, native OSINT workspace anyone can build and audit.
2. Make adding a data source a small, well‑documented contribution.
3. Grow a catalogue of community plugins without compromising safety or quality.

## Phase 0 — Make the repo releasable (pre‑launch)

- [x] One `Plugin` protocol; results are pure value types (done).
- [x] Per‑subsystem docs + plugin authoring guide (this `docs/` folder).
- [x] Professional `README.md`.
- [ ] `LICENSE` (MIT — see below), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` (added).
- [ ] Issue/PR templates incl. a **plugin proposal** template (added under `.github/`).
- [ ] Strip any personal data from sample investigations; ship none by default.
- [ ] CI: `xcodegen generate` + `xcodebuild build` on macOS for every PR (see below).
- [ ] A `CHANGELOG.md` and semantic version tags.

## Phase 1 — Public launch

- Public GitHub repo; enable Discussions and Issues.
- Tag `v1.0.0`; attach a notarised macOS build to the Release (signing is the
  maintainer's; the source builds unsigned for everyone).
- Label good first issues, especially "new plugin: <source>".
- Publish the tool‑coverage map ([OSINT-TOOLS.md](OSINT-TOOLS.md)) as the contribution backlog.

## Phase 2 — Lower the bar to contribute plugins

- A `Plugins/Community/` folder for contributed plugins, reviewed to the same
  checklist as core (see [PLUGIN-DEVELOPMENT.md](PLUGIN-DEVELOPMENT.md#9-checklist-before-opening-a-pr)).
- A **plugin template** (`scripts/new-plugin.sh` or an Xcode file template) that
  scaffolds metadata + `run` + a test stub.
- A lightweight **plugin manifest** (id, category, kinds, auth, maintainer,
  data‑source ToS link) so the catalogue can be generated and audited.
- Golden‑sample tests per plugin (recorded fixtures) so public‑endpoint drift is
  caught without hammering live services in CI.

## Phase 3 — A real ecosystem

- **External plugins.** Because plugins are pure transforms, the long‑term goal is
  to load them without rebuilding the app. Options, in order of effort:
  1. *Compile‑time registry* (today): contribute to `defaultCatalogue`.
  2. *Manifest‑driven HTTP plugins*: a JSON/DSL describing endpoint + field mapping
     for the common "GET JSON → entities" case, interpreted at runtime. Covers a
     large fraction of sources with zero native code and is safe to sandbox.
  3. *WASM/sandboxed plugins*: for arbitrary logic, run untrusted plugins in a
     sandbox with an explicit network/JSON capability surface.
- A community plugin index (a repo of manifests) the app can browse and enable.
- Per‑plugin rate limiting and a shared request budget.

## Governance & quality

- **Review bar**: correctness, noise control (infra filtering, false‑positive
  controls, honest confidence), graceful failure, and respect for source ToS.
- **Maintainers**: start with the founder; add maintainers by sustained
  contribution. Decisions in the open via Issues/Discussions.
- **Security**: see [../SECURITY.md](../SECURITY.md). Plugins are reviewed for SSRF,
  credential handling, and data exfiltration risk before merge.

## Licensing & legal

- **Code license: MIT** — permissive, maximises adoption and plugin contributions.
- **Contributions** are accepted under the project license (inbound = outbound). No
  CLA initially; revisit only if a relicensing need appears.
- **Data‑source compliance is the operator's responsibility.** Each plugin must
  link the source's ToS in `docURL`; plugins that require violating a ToS to
  function are not accepted. The README and in‑app **Responsible use** notice make
  the lawful‑use expectation explicit.
- **Trademark**: keep the "Noeron" name/branding owned by the project; the MIT grant
  covers code, not the mark.

## Continuous integration (suggested)

```yaml
# .github/workflows/build.yml (sketch)
name: build
on: [push, pull_request]
jobs:
  macos:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: cd Noeron && xcodegen generate
      - run: |
          cd Noeron
          xcodebuild -project Noeron.xcodeproj -scheme Noeron_macOS \
            -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Success metrics

- Time‑to‑first‑plugin for a new contributor (target: < 1 hour with the guide).
- Number of keyless plugins (keep keyless the majority).
- % of PRs that pass the noise/quality checklist on first review.
