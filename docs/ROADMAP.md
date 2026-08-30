# Roadmap

Direction, not promises. Sequencing follows the ADRs in [adr/](adr/); each
item lands only with its verification, and `main` stays releasable between
every step. Dates are deliberately absent.

## Where the project is

- **Working emulation** for Mega Drive/Genesis, SNES, and Game Boy/Game Boy
  Advance via bundled, pinned-source cores — all hash-verified by the
  conformance gate (`Scripts/conformance.sh`), in-process and through the
  out-of-process core helper.
- **The helper architecture is real** ([ADR 0006](adr/0006-xpc-core-helper.md)):
  a sandboxed XPC service hosts core sessions with IOSurface frame transport
  and bit-identical output to the in-process path. User-supplied cores are
  probed exclusively inside it — the main app never loads unauthenticated
  code, and never will.

## Near term

- **PlayStation.** A disc-era system, hosted **exclusively in the helper**:
  the main app keeps zero hardened-runtime exceptions and no network access.
  GPL-licensed cores ship with corresponding source (pinned commit, patches,
  build script) published alongside each release. Includes BIOS recognition
  (user-supplied files, staged by content hash), disc-image library handling,
  and sensible large-content policy.
- **Helper playback.** User-supplied cores go from "probed and verified" to
  fully playable — frame pacing, input, and save persistence over the
  process boundary.
- **Library depth.** Title normalization, search, and a grid view; cover art
  stays user-supplied (folder import) — the app does not gain network access
  for artwork or anything else.

## Further out

- **JIT in the helper.** Dynarec cores need W^X memory on Apple Silicon; the
  sanctioned path (`MAP_JIT` + per-thread write protection) will live in the
  helper alone, keeping the main app's hardening intact even when signing
  and notarization resume. Almost no emulation frontend ships this signed —
  that is the point of the process split.
- **A first-class Metal path** for hardware-rendered cores
  (`RETRO_HW_RENDER_INTERFACE`), native rather than translated — the door to
  N64/GameCube-class systems.
- **Upstream contributions.** Where cores lack solid AArch64 support, the
  intent is to contribute upstream rather than fork.
- **Signing and notarization.** The release pipeline already supports both;
  they switch on when the project warrants the membership. The entitlement
  design is arranged so nothing needs re-architecting on that day.

## Explicit non-goals

- No network access in the main app, ever.
- No BIOS files, ROMs, firmware, or decryption keys in the repository,
  releases, or CI — and no acquisition guidance.
- No Intel build.
- No loading of unauthenticated code in the main app process.
