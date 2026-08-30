# ADR 0007: PlayStation via Beetle PSX, helper-only

- Status: Accepted (design; slices land incrementally, each leaving main releasable)
- Date: 2026-08-30

## Context

The out-of-process core helper (ADR 0006) is complete: helper-hosted
sessions produce bit-identical output to the in-process path, and
user-supplied cores are probed exclusively inside it. That unlocks the
first disc-era system — and the first core whose licence forbids the
in-process path. This ADR settles the core choice, the enforcement
mechanism for "helper-only", the GPL distribution obligations, and the
disc-content policies the frontend needs.

## Decisions

1. **Core: Beetle PSX (`mednafen_psx`), pinned, software renderer.**
   GPL-2.0 → helper-only under ADR 0001's curation rule. It builds from a
   pinned commit with plain `make` on arm64 (verified locally and in CI),
   defaults to its CPU interpreter — fast enough on Apple Silicon at many
   multiples of realtime, so no JIT is needed for PlayStation v1 — and its
   software renderer fits the existing `XRGB8888` pixel path.
   *Alternative rejected for now*: SwanStation (GPL-3.0, licence-compatible
   with the app) — heavier CMake build, hardware-render-oriented design,
   and a recompiler-first architecture we don't need yet. Revisit when the
   Metal HW-render path exists.

2. **Helper-only is mechanical, not conventional.** Helper-only cores are
   bundled under `Contents/PlugIns/HelperOnly/`. `CoreTrustPolicy` now
   enforces *direct* containment — a file in a subdirectory of the allowed
   directory is refused — so the app process cannot `dlopen` a helper-only
   core through any code path that goes through the policy (they all do).
   The helper receives the subdirectory as its own allowed directory.
   Keeping the GPL core out of the GPL-incompatible-adjacent process is
   also the strongest arm's-length aggregation argument: the core never
   shares an address space with the GPL-3.0 app.

3. **Corresponding source ships with every release.** The release workflow
   packages the exact pinned Beetle PSX tree (`git archive` of the built
   checkout) plus the build script used, and attaches both to the same
   GitHub release as the app — ADR 0001's GPL obligation made operational.
   The pattern is reusable for every future GPL/LGPL core.

4. **BIOS: user-supplied, recognized by digest, staged canonically.**
   PlayStation cores require the user's own BIOS images under canonical
   names (`scph5500.bin`, `scph5501.bin`, `scph5502.bin`) in the system
   directory root. The frontend recognizes user files by MD5 (names vary
   wildly in the wild), stages verified files under the canonical names in
   the helper's system directory, and reports precisely which region BIOS
   is missing. No BIOS data, names-lists, or acquisition guidance beyond
   digest recognition ever enters the repository.

5. **Disc-content policy.**
   - `.cue` is the routed entry point; the core itself parses the sheet and
     opens sibling `.bin` tracks (the helper only needs plain read access to
     the content's directory, which the session's scoped grant provides).
   - Disc content is passed by path only (`need_fullpath` honored) — the
     host never slurps a multi-hundred-MB image into memory.
   - The cartridge-sized content cap stays for cartridge extensions; disc
     extensions are exempt from it and instead validated by type routing.
   - The library scanner hides `.bin`/`.img`/`.iso` files that sit next to
     a `.cue` naming them, so discs appear once, not as track garbage.
   - Multi-disc (`.m3u`, disk-control interface) is deferred until after
     single-disc play is solid.

6. **Deferred, explicitly.** `RETRO_ENVIRONMENT_GET_VARIABLE` support
   (Beetle's compiled defaults are correct for v1); SwanStation;
   hardware-rendered PSX; dynarec/JIT (tracked by ADR 0006 decision 5 —
   only an inert helper entitlements file lands ahead of need).

## Consequences

- The app bundle becomes a mixed distribution: non-commercial cores
  (no-sale constraint), MPL, and now GPL-2.0 — each a separate aggregated
  work with its licence text in the bundle and its row in THIRD_PARTY.md.
- The helper's play path (pacing, input, and save persistence over XPC)
  becomes a hard dependency for shipping this system; it is the phase's
  keystone rather than an optimization.
- The trust-policy tightening (direct containment) is a behavioral change
  for any future consumer that expected nested plug-in directories to load
  in-process; that expectation is now an error by design.
