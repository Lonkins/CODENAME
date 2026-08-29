# CODENAME

A native Apple Silicon (arm64) macOS frontend for [libretro](https://www.libretro.com/) cores, built for game preservation and research.

Swift 6, Metal presentation, macOS 15+. Signed, notarized, sandboxed, and Gatekeeper-clean by design — the security posture is the point, not an afterthought: the app ships with **zero** hardened-runtime exceptions (see [ADR 0001](docs/adr/0001-core-loading-and-entitlements.md)).

## Status: pre-alpha

Phase 0 (foundations) is in place: CI on arm64 runners, a tag-driven release pipeline (Developer ID signing → notarization → stapled `.dmg`), and a [Sparkle](https://sparkle-project.org) update channel with an EdDSA-signed [appcast](https://lonkins.github.io/CODENAME/appcast.xml).

**There is no emulation yet.** Phase 1 (the libretro core host: video, audio, input, save states) is next. Current [releases](../../releases) are unsigned pipeline dry-runs and will not pass Gatekeeper; real signed releases begin once notarization credentials are configured.

## What this is

- A macOS-native host application that loads libretro emulator cores and presents them through Metal, with system-standard audio (`AVAudioEngine`), input (`GameController` — DualSense, Xbox, 8BitDo, keyboard), and windowing.
- arm64 only, macOS 15.0 minimum. No Intel build, no universal binary.
- Curated emulator cores are bundled with releases as separately licensed plug-in works; the app never loads unsigned code (details and rationale in [ADR 0001](docs/adr/0001-core-loading-and-entitlements.md)).

## What this is not

- Not an emulator. Emulation comes from actively maintained upstream libretro cores.
- This project contains no BIOS files, ROMs, firmware, or decryption keys, and provides no guidance on acquiring them. Users supply their own legally obtained content.

## Building from source

Apple Silicon Mac with Command Line Tools (full Xcode not required):

```
./Scripts/make-app.sh
open build/CODENAME.app
```

Tests and lint: `swift test --package-path Packages/CODENAMEKit` (requires Xcode toolchain) and `swift format lint --strict --recursive Packages`. Release packaging is documented in [docs/RELEASING.md](docs/RELEASING.md). A Homebrew cask stub lives in [Casks/](Casks/) pending signed releases.

## Design decisions

Recorded as ADRs in [docs/adr/](docs/adr/): core loading & entitlements (0001), project format (0002). Frame pacing (0003) precedes the Phase 1 renderer.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — DCO sign-off required, third-party provenance rules, no content material of any kind. Security reports: [SECURITY.md](SECURITY.md).

## License

GPL-3.0-or-later ([LICENSE](LICENSE)). Bundled cores and dependencies are separate works listed in [THIRD_PARTY.md](THIRD_PARTY.md).
