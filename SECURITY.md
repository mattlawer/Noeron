# Security policy

## Reporting a vulnerability

Please report security issues **privately**, not as public issues.

- Use GitHub's **"Report a vulnerability"** (Security → Advisories) on the repo, or
- email the maintainer (address in the repo profile / `git log`).

Include: affected version/commit, a description, reproduction steps, and impact.
We aim to acknowledge within a few days and to coordinate a fix and disclosure
timeline with you.

## Scope

Noeron is a local, on‑device app with no backend. The most relevant classes of
issue:

- **Credential handling** — API keys live in the macOS Keychain and must never be
  written to the SwiftData/CloudKit store, logs, reports, or the graph.
- **SSRF / request safety in plugins** — a plugin must only contact its intended
  data source and must not be coercible into requesting attacker‑controlled hosts
  via unvalidated input.
- **Data exfiltration** — plugins must not send investigation data anywhere except
  the documented query to their source.
- **Parsing safety** — defensive decoding; never crash on hostile responses.

## Plugin review

Every plugin is reviewed for the above before merge. If you find a plugin that
violates these properties, report it as a vulnerability rather than a public issue.

## Responsible use

Noeron is built for lawful, authorised investigation. Reports about features being
used to violate a data source's terms or applicable law are handled as policy
issues; see the **Responsible use** sections in the README and in‑app About tab.
