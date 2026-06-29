# OSINT tools → Noeron plugins

A survey of the best-known OSINT tools, what each does, and how Noeron covers the
capability. **Keyless** plugins run with nothing configured — they are what makes
Noeron useful the moment you open it. **Key** plugins light up once you add the
relevant API key in Settings.

Legend: ✅ keyless plugin · 🔑 key-based plugin · 🟡 partial / best-effort · ⬜ not yet

---

## Domains & infrastructure

| Tool | What it does | Noeron |
|---|---|---|
| **WHOIS** clients | Registrar, registrant, lifecycle dates | ✅ `WHOIS` (port-43, IANA referral) |
| **dig / dnsx / DNSRecon** | A/AAAA/MX/NS/CNAME/TXT records | ✅ `DNS` (DNS-over-HTTPS) |
| **Amass / Subfinder / theHarvester / Sublist3r** | Passive subdomain enumeration from many sources | ✅ `Subdomain Enumeration` (HackerTarget, AlienVault OTX, Certspotter, RapidDNS) + ✅ `SSL Certificates` (crt.sh CT logs) |
| **crt.sh / CertSpotter / Censys CT** | Certificate Transparency → certs + SAN subdomains | ✅ `SSL Certificates` (crt.sh) |
| **dnstwist / URLCrazy** | Typosquat / look-alike domain generation + resolution | ✅ `Typosquat / Look-alikes` |
| **Wayback Machine / waybackurls / gau** | Archived URLs & historical footprint | ✅ `Wayback Machine` (Archive CDX) |
| **HackerTarget / ViewDNS reverse IP** | Domains co-hosted on an IP, PTR | ✅ `Reverse IP / PTR` |
| **SecurityTrails** | Historical DNS / passive DNS | 🔑 `Historical DNS` |
| **urlscan.io** | Page scans, related infra, screenshots | ✅ `urlscan.io` (search API) |
| **Shodan** | Open ports, banners, exposed services | ✅ `Shodan InternetDB` (free, keyless — ports/CVEs/hostnames) · 🔑 `Shodan` (paid, full) |
| **Censys** | Host/cert search, ASN data | 🔑 `Censys` |
| **VirusTotal** | Reputation, passive DNS resolutions | 🔑 `VirusTotal` |
| **BuiltWith / Wappalyzer** | Technology stack fingerprinting | ⬜ |

## IP & network

| Tool | What it does | Noeron |
|---|---|---|
| **ipinfo / ip-api / ipwho.is** | Geolocation, ISP, ASN, org | ✅ `IP Geolocation` (ipwho.is) |
| **BGPView / Hurricane Electric** | ASN → prefixes, peers, owning org | ✅ `ASN` (BGPView) |
| **HackerTarget reverse IP** | Co-hosted domains, PTR | ✅ `Reverse IP / PTR` |

## Email

| Tool | What it does | Noeron |
|---|---|---|
| **Holehe** | Which sites an email is registered on | ✅ `Account Existence` (Firefox, Duolingo, Spotify) 🟡 |
| **Hunter.io** | Emails for a domain, patterns | 🔑 `Hunter` |
| **Have I Been Pwned / Mozilla Monitor** | Breaches an email appears in | ✅ `XposedOrNot` (free, keyless — default) · 🔑 `HaveIBeenPwned` (paid, fuller) |
| **EmailRep** | Reputation, breach flags, linked profiles | ✅ `EmailRep` (free tier) 🟡 |
| **Gravatar lookups** | Avatar + public profile + linked accounts | ✅ `Gravatar` |
| **theHarvester (email mode)** | Harvest addresses from public sources | 🟡 via `Hunter` 🔑 / `Email Intelligence` derivation |
| **Mosint** | Aggregated email OSINT | 🟡 combination of the email plugins |
| *(Noeron original)* | Parse domain+username, provider/MX/disposable, fan-out | ✅ `Email Intelligence` |
| *(Noeron original)* | GitHub identity behind an email via commits | ✅ `GitHub (commit email)` |

## Usernames & social

| Tool | What it does | Noeron |
|---|---|---|
| **Sherlock / Maigret / WhatsMyName** | One username across hundreds of sites | ✅ `Username Sweep` (~40 sites, data catalogue) |
| **GitHub OSINT** | Profile, repos, commit emails | ✅ `GitHub` + ✅ `GitHub (commit email)` |
| **Reddit / Mastodon / Bluesky tools** | Profile, karma, instance, DID | ✅ `Reddit`, ✅ `Mastodon`, ✅ `Bluesky` |
| **GHunt** | Google account (needs cookies) | ⬜ (auth-gated) |
| **Twint / snscrape** | Twitter/X scraping | ⬜ (auth-gated since API lockdown) |

## Phone

| Tool | What it does | Noeron |
|---|---|---|
| **PhoneInfoga** | Format, country/carrier, footprint dorks | ✅ `Phone Intelligence` (country via calling code, E.164, WhatsApp + search pivots) 🟡 |
| **Numverify / OpenCNAM** | Carrier / line type | ⬜ (paid HLR APIs) |

## People, companies & knowledge

| Tool | What it does | Noeron |
|---|---|---|
| **Wikidata / Wikipedia** | Entities, official sites, inception | ✅ `Wikidata` |
| **Pappers / Societe.com / Infogreffe** | French company records (SIREN, officers, accounts) | ✅ `Company Registry` (keyless gov API `recherche-entreprises.api.gouv.fr` + Pappers/Societe.com document links) |
| **OpenCorporates** | Global company registry aggregator | ✅ `Company Registry` (search links) · 🔑 `OpenCorporates` (structured) |
| **Companies House / North Data / national registries** | UK & EU company filings/officers | ✅ `Company Registry` (per-country search links) · 🔑 `Companies House` |
| **SEC EDGAR** | US public-company filings | ✅ `SEC EDGAR` + `Company Registry` link |
| **Pipl / Spokeo / that's-them** | People search | ⬜ (paid / consent-gated) |
| **LinkedIn (Proxycurl)** | Professional profile | 🔑 `LinkedIn` |

## Blockchain / on-chain

| Tool | What it does | Noeron |
|---|---|---|
| **Blockchair / blockchain.com explorers** | Bitcoin address balance, totals, activity | ✅ `Bitcoin On-chain` (Blockstream Esplora, keyless) |
| **Etherscan / Ethplorer** | ETH balance, tokens, transactions | ✅ `Ethereum On-chain` (Blockscout, keyless) |
| **Solscan / Solana Explorer** | SOL balance, SPL tokens, activity | ✅ `Solana On-chain` (public RPC, keyless) |
| **Chainalysis / Breadcrumbs (wallet clustering)** | Related wallets / counterparties | ✅ co-spend heuristic + recent counterparties via the on-chain plugins |

## Geo, media & breach

| Tool | What it does | Noeron |
|---|---|---|
| **Nominatim / OpenStreetMap** | Place → coordinates / canonical name | ✅ `Geocoding (OSM)` |
| **ExifTool** | Image/file metadata (GPS, camera, dates) | ⬜ (planned: local ImageIO on `.image` evidence) |
| **Intelligence X** | Leaks, pastes, dark-web references | 🔑 `Intelligence X` |
| **Telegram OSINT** | Channel/user lookups | 🔑 `Telegram` |
| **Google dorking (GHDB / dork lists)** | Operator searches for exposed files, configs, credentials, leaks, profiles | 🔑 `Google Dorks` (SerpAPI or Google Custom Search; curated dorks per selector) |

---

## How discovery uses these

Noeron's discovery engine is breadth-first: a seed runs every applicable enabled
plugin, and each **discovered** node (a subdomain, IP, username, domain, location…)
is itself expanded up to the depth limit. Because the keyless plugins emit
pivotable nodes — `Email Intelligence` yields a domain + username, `Subdomain
Enumeration` yields hosts that `DNS`/`SSL` then expand, `Reverse IP` yields
co-hosted domains — a single selector cascades into a broad graph **without any
API key**. Keys only add depth (Shodan ports, HIBP breaches, etc.), never gate the
core experience.

## Adding coverage

- **A new site for a username** → add one row to `UsernameSweepPlugin.catalogue`.
- **A new passive subdomain source** → add one `async let` source in `SubdomainEnumPlugin`.
- **A whole new source** → copy any plugin in `Plugins/Live/`, implement `run`, and
  register it in `PluginRegistry.defaultCatalogue`. Keyless plugins with
  `requiresAPIKey: false` are enabled automatically.
