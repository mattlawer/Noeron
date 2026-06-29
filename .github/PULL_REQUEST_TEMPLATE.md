## What & why
<!-- What does this change and why? Link the issue. -->

Closes #

## Type
- [ ] New plugin
- [ ] Bug fix
- [ ] Feature / UI
- [ ] Docs

## Checklist
- [ ] Builds clean: `xcodebuild -project Noeron.xcodeproj -scheme Noeron_macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Re‑ran `xcodegen generate` if files were added/removed
- [ ] Docs updated (and `docs/OSINT-TOOLS.md` if a source was added)
- [ ] No secrets / personal sample data; `Noeron.xcodeproj` not committed

## For plugins
- [ ] Completed the checklist in `docs/PLUGIN-DEVELOPMENT.md`
- [ ] Registered in `PluginRegistry.defaultCatalogue`
- [ ] Noise control applied (infra filtering, false‑positive control, honest confidence)
- [ ] `docURL` set; data source's ToS permits this use
