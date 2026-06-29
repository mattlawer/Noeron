# Building Noeron

## Requirements

- macOS with **Xcode 16+** (macOS 14 / iOS 17 SDKs).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

The Xcode project is generated from `project.yml` and is **not** committed — run
XcodeGen after cloning and after any change to the file list.

## Generate & open

```bash
brew install xcodegen
cd Noeron
xcodegen generate          # creates Noeron.xcodeproj
open Noeron.xcodeproj
```

Schemes: `Noeron_macOS` and `Noeron_iOS`.

## Run in Xcode

1. **Signing** — set your Team in *Signing & Capabilities* (or `DEVELOPMENT_TEAM`
   in `project.yml`).
2. Pick the **Noeron** scheme and a destination (Mac, iPad, iPhone) and Run.

## Command‑line build check (no signing)

```bash
xcodebuild -project Noeron.xcodeproj -scheme Noeron_macOS \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## iCloud sync (optional)

CloudKit turns on **only** when the build is signed with the iCloud entitlement for
the container `iCloud.com.noeron.app`. With no/empty entitlements the app runs on a
local store and never touches CloudKit (the container factory checks the
entitlement at runtime first, because a CloudKit call without it is a hard crash).
To enable sync, add the iCloud capability + container in *Signing & Capabilities*
and change the bundle id / container to your own.

## Keychain prompts on unsigned builds

On an **unsigned/ad‑hoc** build macOS may prompt the first time a plugin's stored
API key is read (when you *run* a key‑based plugin). Click "Always Allow". Browsing
never prompts — the UI reads only a non‑secret index, not the Keychain (see
`Support/KeychainStore.swift`). Signing with your Developer Team removes the prompt
entirely.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "does not contain a scheme named Noeron" | use `Noeron_macOS` / `Noeron_iOS`; re‑run `xcodegen generate` |
| CloudKit crash on launch | you're signed with the iCloud entitlement but the container isn't set up — remove the entitlement or configure the container |
| A plugin returns nothing | public endpoints change/rate‑limit; check the **Plugin Log** for the raw excerpt |
