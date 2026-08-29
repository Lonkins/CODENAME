# Third-party code and dependencies

Every third-party dependency, vendored file, or adapted snippet is recorded here with its licence. No code enters this repository without a licence check (see [CONTRIBUTING.md](CONTRIBUTING.md)).

| Component | Version | Licence | Usage | Source |
|-----------|---------|---------|-------|--------|
| Sparkle | 2.9.6 | MIT | Application updates (EdDSA-signed appcast); framework embedded in the app bundle | https://github.com/sparkle-project/Sparkle |
| libretro.h | libretro-common @ `c68f624` | MIT-style (notice preserved in file) | Vendored libretro C ABI header (`Packages/CODENAMEKit/Sources/CLibretro/include/libretro.h`) | https://github.com/libretro/libretro-common |
| Genesis Plus GX | @ `a7985a9` | Non-commercial (see `App/CoreLicences/genesis_plus_gx.txt`) | Emulator core, built from pinned source by `Scripts/build-cores.sh`, bundled with app builds as a separate plug-in work (ADR 0001) | https://github.com/libretro/Genesis-Plus-GX |
| Snes9x | @ `890b5d4` | Non-commercial (see `App/CoreLicences/snes9x.txt`) | Emulator core, built from pinned source by `Scripts/build-cores.sh`, bundled with app builds as a separate plug-in work (ADR 0001) | https://github.com/libretro/snes9x |

Emulator cores never live in this repository. Release builds bundle a small curated set of cores as separate, individually licensed plug-in works aggregated with the app (see `docs/adr/0001-core-loading-and-entitlements.md`); each bundled core is recorded in the table above with its licence and source reference when added.
