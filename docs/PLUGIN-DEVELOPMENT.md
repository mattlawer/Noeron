# Writing a Noeron plugin

A plugin is the unit of OSINT capability in Noeron. It is a small, `Sendable` type
that transforms one entity into structured findings:

```
EntitySnapshot  ──(network / compute)──▶  PluginResult
```

Plugins never touch SwiftData or the UI. The `DiscoveryEngine` runs them off the
main actor and writes their results into the graph. That makes plugins easy to
write, easy to test, and safe to run concurrently.

> Prerequisites: skim [ARCHITECTURE.md](ARCHITECTURE.md) and [DATA-MODEL.md](DATA-MODEL.md)
> first — this guide uses their vocabulary (`EntityKind`, `LinkKind`, attributes).

## 1. The protocol

```swift
protocol Plugin: Sendable {
    var metadata: PluginMetadata { get }
    func canRun(on entity: EntitySnapshot, context: PluginContext) -> Bool   // has a default
    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult
}
```

The default `canRun` returns `true` when the entity's kind is in
`metadata.acceptedKinds` **and** any required credentials are present. Override it
only for custom gating (e.g. "either of two providers configured").

## 2. Metadata

```swift
PluginMetadata(
    id: "my-source",                 // stable, unique, kebab-case — persisted in the enabled set
    name: "My Source",
    summary: "One line describing what it returns.",
    category: .network,              // network/breach/social/corporate/blockchain/threat/knowledge
    acceptedKinds: [.domain],        // which kinds this plugin runs on
    producesKinds: [.ipAddress],     // which kinds it can emit (documentation/UI only)
    requiresAPIKey: false,           // true → not auto-enabled until a key is saved
    credentialFields: [],            // [CredentialField] — secret API keys (Keychain)
    parameterFields: [],             // [ParameterField] — non-secret config (UserDefaults)
    docURL: "https://…",             // shown in the plugin detail view
    isLive: true,                    // true = makes real network calls in this build
    symbol: "globe"                  // SF Symbol
)
```

**Credentials vs. parameters.** Secret keys go in `credentialFields` and are read at
run time via `context.credential("my.apiKey")` (stored in the Keychain). Non-secret,
user-editable settings — a custom RPC endpoint, an instance URL — go in
`parameterFields` and are read via `context.parameter("my.rpcBase")` (stored in
UserDefaults). Both are editable from the **plugin detail view** (Settings → tap a
plugin). Example: the blockchain plugins expose a custom RPC/explorer base this way.

## 3. Returning results

Build a `PluginResult`:

```swift
struct PluginResult {
    var entities: [DiscoveredEntity] = []   // new nodes + how they link to the input
    var events: [DiscoveredEvent] = []      // dated facts for the timeline
    var inputAttributes: [EntityAttribute] = []  // facts to attach to the INPUT entity
    var rawExcerpt: String = ""             // first KB of the raw response, for the audit log
    var sample: Bool = false                // true only for non-live sample data
}
```

A `DiscoveredEntity` is a node plus its edge back to the input:

```swift
DiscoveredEntity(
    kind: .ipAddress,
    label: "93.184.216.34",
    subtitle: "A record",
    confidence: 0.95,                // 0…1
    attributes: [.init(key: "TTL", value: "300", kind: .number, source: "My Source")],
    sourceURL: "https://…",
    linkKind: .resolvesTo,           // semantic edge label
    linkDirection: .fromInput        // .fromInput: input → finding · .toInput: finding → input
)
```

`linkDirection` follows the `LinkKind` comment. Example: a person *has* an email,
so a Person finding for an email input uses `linkKind: .hasEmail, linkDirection: .toInput`
(the edge goes person → email).

## 4. Networking

Use the helpers on `PluginContext` — they set a polite User‑Agent, map HTTP 429 to
`PluginError.rateLimited`, and decode JSON:

```swift
let (data, http) = try await context.get(url, headers: ["Accept": "application/json"], timeout: 15)
let model      = try await context.getJSON(MyResponse.self, from: url)
let text       = try await context.getString(from: url)
```

For credentials (key‑based plugins): `context.credential("serpapi.apiKey")` returns
the stored key or `nil`. **Read keys only inside `run`**, never to render UI.

## 5. A complete example

```swift
import Foundation

struct DNSResolvePlugin: Plugin {
    var metadata: PluginMetadata {
        .init(id: "dns-a", name: "DNS A Record",
              summary: "Resolves a domain's IPv4 addresses over DNS-over-HTTPS.",
              category: .network, acceptedKinds: [.domain, .subdomain],
              producesKinds: [.ipAddress], isLive: true,
              symbol: "antenna.radiowaves.left.and.right")
    }

    private struct DoH: Decodable {
        let Answer: [A]?
        struct A: Decodable { let type: Int; let data: String }
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        let domain = WhoisPlugin.normalize(entity.label)   // shared label helper
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        comps.queryItems = [.init(name: "name", value: domain), .init(name: "type", value: "A")]
        let resp = try await context.getJSON(DoH.self, from: comps.url!,
                                             headers: ["Accept": "application/dns-json"])

        var result = PluginResult(rawExcerpt: "A lookup for \(domain)")
        for a in (resp.Answer ?? []) where a.type == 1 {
            guard !InfraFilter.isInfrastructure(a.data) else { continue }   // drop infra noise
            result.entities.append(.init(
                kind: .ipAddress, label: a.data, subtitle: "A record",
                confidence: 0.95, linkKind: .resolvesTo, linkDirection: .fromInput))
        }
        return result
    }
}
```

## 6. Register it

Add an instance to `PluginRegistry.defaultCatalogue` (`Plugins/PluginRegistry.swift`),
in the matching section. Keyless live plugins (`isLive: true, requiresAPIKey: false`)
are enabled for automatic discovery by default; key‑based plugins switch on when
their key is saved.

Create **one file per plugin** (named after the plugin) in the matching folder:

- `Plugins/Live/` — keyless plugins that make real network calls.
- `Plugins/Public/` — keyless public‑source plugins (Wikidata, SEC, Reddit, …).
- `Plugins/KeyBased/` — services that require an API key.

Shared helpers (`ISO8601Date`, `String.pathEncoded`/`basicAuthHeader`, the
`decode(_:_:)` JSON helper, `Array[safe:]`) live in `Plugins/Shared/PluginHelpers.swift`
— reuse them rather than redefining. New files are picked up automatically on the
next `xcodegen generate`.

## 7. Avoiding noise

This is what separates a useful plugin from one that floods the graph:

- **Don't emit infrastructure as nodes.** Filter hostnames with
  `InfraFilter.isInfrastructure(_:)`; don't pivot on free webmail
  (`InfraFilter.isFreeWebmail(_:)`).
- **Prefer attributes over nodes** for things that won't be expanded (search URLs,
  registry record links, raw flags). Only emit a node when expanding it adds value.
- **Use `.document` kind** for reference URLs you don't want crawled (no plugin
  accepts `.document`, so it won't expand).
- **Eliminate false positives with a control.** For existence checks, also test a
  value that cannot exist and discard the source if it "matches" anyway (see
  `UsernameSweepPlugin`).
- **Set honest confidence.** Unverified search hits ≈ 0.4; a strong API match ≈ 0.9.
- **Degrade gracefully.** Catch and ignore per‑source failures (`try?`); return
  `.empty` or a `rawExcerpt` note rather than throwing for "no data".

## 8. Testing

Tests live in **`NoeronTests/`** and run via the **"Noeron (macOS + Tests)"** scheme:

```bash
cd Noeron
xcodebuild test -project Noeron.xcodeproj -scheme "Noeron (macOS + Tests)" \
  -destination 'platform=macOS'
```

A plugin is a pure function of `(EntitySnapshot, PluginContext)`, so it is unit‑
testable without the app and **without the network** — the deterministic parts
(parsing, classification, de‑dup) are what you assert on. Prefer testing the pure
helpers your plugin relies on (`CryptoAddress.chain`, `EmailIntel.parts`,
`InfraFilter.isInfrastructure`, your own parsing functions) over hitting live
endpoints. Pattern:

```swift
import XCTest
@testable import Noeron

final class MySourceTests: XCTestCase {
    func testParsesResponse() throws {
        // Feed a captured JSON fixture into your Decodable / parsing helper and
        // assert the entities/attributes you expect — no PluginContext needed.
    }
    func testAddressClassification() {
        XCTAssertEqual(CryptoAddress.chain(of: "0x" + String(repeating: "a", count: 40)), .ethereum)
    }
}
```

To drive `run(on:context:)` itself offline, inject a `PluginContext` with custom
`credentialProvider` / `parameterProvider` closures. Add at least one deterministic
test for any new parsing or classification logic; keep network calls out of CI.

## 9. Checklist before opening a PR

- [ ] `id` is unique, stable, kebab‑case.
- [ ] `acceptedKinds` / `producesKinds` are accurate; `summary` is one clear line.
- [ ] `requiresAPIKey` + `credentialFields` (secrets) and `parameterFields` (config) set correctly; `docURL` points to real docs.
- [ ] Infra/noise filtering applied; confidence values are honest.
- [ ] A unit test covers new parsing/classification logic (`NoeronTests/`).
- [ ] Failures are non‑fatal; the build passes (`xcodebuild … build`) and tests pass.
- [ ] Registered in `PluginRegistry.defaultCatalogue`.
- [ ] Updated [OSINT-TOOLS.md](OSINT-TOOLS.md) if it maps to a known tool.

See [../CONTRIBUTING.md](../CONTRIBUTING.md) for the PR workflow.
