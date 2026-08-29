# Third-party code and dependencies

Every third-party dependency, vendored file, or adapted snippet is recorded here with its licence. No code enters this repository without a licence check (see [CONTRIBUTING.md](CONTRIBUTING.md)).

| Component | Version | Licence | Usage | Source |
|-----------|---------|---------|-------|--------|
| Sparkle | 2.9.6 | MIT | Application updates (EdDSA-signed appcast); framework embedded in the app bundle | https://github.com/sparkle-project/Sparkle |

Planned (recorded here when actually added):

- **libretro-common headers** — MIT — libretro C ABI definitions for the core host.

Emulator cores never live in this repository. Release builds bundle a small curated set of cores as separate, individually licensed plug-in works aggregated with the app (see `docs/adr/0001-core-loading-and-entitlements.md`); each bundled core is recorded in the table above with its licence and source reference when added.
