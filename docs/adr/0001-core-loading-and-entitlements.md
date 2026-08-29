# ADR 0001: Core loading and entitlements

- Status: **Accepted** (maintainer approval 2026-08-29)
- Date: 2026-08-29

## Context

CODENAME loads libretro emulator cores — third-party native `.dylib` code. The app must be Developer ID signed, notarized, and Hardened-Runtime-enabled from the first release; that is the project's differentiator over existing forks.

These goals collide in three places:

1. **Library validation.** Under Hardened Runtime, a loaded library must be signed by Apple or by the same Team ID as the host app. Upstream buildbot cores are unsigned; `dlopen` fails.
2. **Gatekeeper.** Files downloaded by a sandboxed app get the quarantine xattr automatically, and a sandboxed app cannot remove it. Quarantined dylibs are assessed at first `dlopen`; Developer-ID-signed but un-notarized code is blocked. A bare `.dylib` cannot carry a stapled notarization ticket, so runtime-downloaded cores would need an online ticket lookup at first load — failing offline. Any design that downloads cores at runtime inherits this.
3. **JIT.** Dynarec cores need W^X memory, which Apple Silicon permits only via `com.apple.security.cs.allow-jit` + `mmap(MAP_JIT)` + per-thread `pthread_jit_write_protect_np` toggling.

This decision shapes process architecture, core distribution, and licensing posture. It is settled before any loader code.

## Threat model

Assets: the user's machine and data; the app's notarized/trusted status; the project's reputation.

1. **Malicious or compromised core binary** — a core is arbitrary native code with the privileges of whatever process hosts it. Sources: compromised upstream, tampered download, or a hostile "core" from the web.
2. **Malicious content files exploiting a legitimate core.** Emulator RCEs are historically real. Signing does nothing against this: the exploited code is authentic. The mitigations are process privilege reduction (sandbox, no network) and, ultimately, out-of-process isolation.
3. **Compromise of our own build/signing infrastructure**, if we redistribute core binaries.
4. Out of scope: a user attacking their own machine; DRM concerns (no keys, no BIOS, ever).

Key asymmetry: cores we build from pinned upstream sources and sign are *authenticated* code with known provenance. An arbitrary dylib supplied by the user is *unauthenticated*. These deserve different trust levels.

## Options

### 1. `com.apple.security.cs.disable-library-validation` on the main app

Any dylib loads. Notarization accepts the entitlement (it is the documented path for plugin hosts; RetroArch, OBS and most DAWs ship it).

- ✅ Trivial; every core works; what existing forks do.
- ❌ Disables code-injection protection for the whole app. Combined with `allow-jit` later, a notarized arbitrary-code host. The project's differentiator, spent in release one.

### 2. Runtime-downloaded cores, signed by us, verified before `dlopen`

A project pipeline builds/ingests cores, signs them with our Team ID, publishes them with a signed manifest; the app verifies then loads. Library validation stays on (same-team dylibs pass).

- ✅ Full hardening on the app.
- ❌ The Gatekeeper problem above: downloaded cores must be individually notarized and can't be stapled as bare dylibs; offline first-load breaks.
- ❌ A hidden second project: per-core build/sign/publish, manifest and key management, revocation, upstream-tracking — for a solo-maintained pre-alpha. Cost grows with upstream build-system diversity.
- ❌ App-level manifest/cdhash checks add little: kernel library validation is the actual load-time control; a swap-in-place attacker already has local code execution (out of scope). The manifest is version pinning, not a security control, and its signing key is a new compromise domain.

### 3. Out-of-process core host (XPC helper)

Cores load only in a bundled helper carrying the weakening entitlements (`disable-library-validation`, later `allow-jit`) under a tight sandbox (no network; files via handed-over descriptors). Frames over IOSurface, audio over shared memory, control over XPC. Entitlements are per-executable, so this split is fully supported; the helper must itself enable Hardened Runtime to notarize.

- ✅ Best containment: hostile cores and exploited-core payloads land in a low-privilege, no-network process. Crash isolation. Proven latency-viable (OpenEmu, WebKit).
- ✅ Cleanest licensing posture: cores stay at maximal arm's length from the GPL-3.0-or-later app.
- ✅ JIT entitlement, when dynarec cores arrive, lands on the helper only.
- ❌ Highest engineering cost, and not a "transport swap": the libretro environment callback returns pointers the core retains (`GET_VARIABLE`, directory paths, a log function pointer), `retro_get_memory_data` exposes live core RAM, and video/audio callbacks hand short-lived pointers. An out-of-process host needs its own full environment implementation and a copy discipline. Deferring this is fine; pretending it is trivial is not.

### 4. Hybrid: option 2 for curated cores + option 3 for user-supplied

Original proposal. Inherits option 2's pipeline and Gatekeeper costs for the curated path.

### 5. Bundled curated cores now, helper later — **chosen**

Phase 1 ships its two cores (`genesis_plus_gx`, `snes9x`) **inside the app bundle**: built in the app's own CI from pinned upstream commits, code-signed with the app's Team ID as bundle plug-ins, notarized as part of the app. Library validation on. App Sandbox on. Zero Hardened Runtime exceptions. No network entitlement on the main app (update downloads go through Sparkle's XPC services). Cores update by app update — correct at this scale, since a two-core pre-alpha releases frequently anyway.

User-supplied or unsigned cores do not load: a precise error states this and points at the roadmap. When unauthenticated cores are scheduled (Phase ≥2), they load exclusively via the option-3 helper; the JIT entitlement, when needed, also lands there.

**Invariant, permanent: the main app never gains a Hardened Runtime exception or weakening entitlement.**

- ✅ Simpler *and* more secure than option 2: no download path means no quarantine/notarization-of-dylibs problem, no manifest, no second pipeline, no TOCTOU (the app bundle is sealed by its signature), and the main app can drop network access entirely — which directly shrinks the blast radius of threat 2, the historically real one.
- ✅ Supply chain: cores built from pinned commits in public CI beats "ingest and sign" provenance.
- ❌ Bundling third-party cores tightens the licensing coupling (next section) and makes us their distributor.
- ❌ Until the helper ships, CODENAME plays exactly two systems. That is a deliberate pre-alpha scope, stated openly, and the popular-fork pressure ("just disable library validation") is an accepted reputational risk — the differentiator *is* not doing that.

## Licensing constraints (binding on the curated set)

- `genesis_plus_gx` and `snes9x` are **non-commercial** licensed, not GPL, and GPL-incompatible. They are distributed *aggregated* with, not combined into, the GPL-3.0-or-later app: separate signed plug-in bundles, loaded across the published libretro ABI, each shipping its own licence text and source reference. Their terms bind us as a distributor: **no sale of the app or any bundle containing them, ever**, and origin must not be misrepresented.
- Curation rule: a core is eligible for bundling only if its licence permits our redistribution and coexistence-by-aggregation. GPLv2-only and LGPL cores are **helper-only** (LGPL relinkability cannot be honored by a load path that refuses user-modified libraries) unless a documented, tested self-sign developer path exists. For any GPL/LGPL core we ever distribute, corresponding source (exact commit, patches, build script) is published as a CI artifact of the same release.
- `THIRD_PARTY.md` and an in-app licences panel record every bundled core.

## App Sandbox

Adopted for the main app from Phase 1. Content directories arrive via `NSOpenPanel` → app-scoped security-scoped bookmarks (`com.apple.security.files.bookmarks.app-scope`), persisted and re-resolved lazily (per scan/launch, never a launch-time sweep); the bookmark lifecycle is one module with tests. No `com.apple.security.network.client` on the main app. The Phase ≥2 helper gets its own tighter profile and receives files by descriptor/security-scoped URL over XPC — helper containers do not see the app's container by default.

**Amendment (2026-08-29, Phase 2):** the entitlement set grows by exactly two keys — `com.apple.security.files.user-selected.read-only` and `com.apple.security.files.bookmarks.app-scope`. These are App Sandbox **scope-extension grants**: they let the *user* extend the sandbox to paths they explicitly pick in the powerbox; they grant the app nothing unilaterally. They are not Hardened Runtime exceptions (the `cs.*` family), which weaken code-integrity protections process-wide. The permanent invariant is unchanged and its meaning is fixed here: "weakening entitlement" means Hardened Runtime `cs.*` keys plus unilateral network/device grants — not user-mediated file access. Read-only is sufficient and deliberate: cores write SRAM and save states only to the container directory the host supplies via `GET_SAVE_DIRECTORY`; saves never live next to content. `user-selected.read-write`, document-scoped bookmarks, and every `temporary-exception` key remain forbidden. Boundary hygiene at scan/open: skip symlinks, cap file sizes per extension, surface scope-acquisition failures as their own error (never as a content rejection), and never log content paths or filenames at default log level — users paste logs into public issue trackers.

## JIT (recorded for Phase ≥2)

`allow-jit` + `MAP_JIT` + `pthread_jit_write_protect_np(0/1)` per thread is the sanctioned Apple Silicon W^X path and matches what upstream dynarecs already do inside signed RetroArch. Watch items: macOS 14.4+ `com.apple.security.cs.jit-write-allowlist` (stricter; disables the pthread toggle; unusable without upstream changes) and unresolved reports of `allow-jit` behavior changes on macOS 26 — re-verify when scheduling dynarec cores.

## Phase 1 design constraints (so the helper stays reachable)

Four things are shaped for process separation from day one — each is also the correct in-process design, so the cost is ~zero:

1. Frame handoff via an IOSurface-backed texture; the core's framebuffer pointer never escapes the session layer.
2. Audio through a lock-free SPSC ring between core thread and render callback (relocatable to shared memory later).
3. The core confined to a dedicated thread; all app↔core interaction is message-shaped.
4. A fallible, restartable session lifecycle: session methods `throws` and can report session death, even though Phase 1 never produces that case. Consumers of `retro_get_memory_data` get snapshot/copy semantics, never a retained live pointer.

**Phase 1 exit criterion:** a one-page transport contract documenting frame lifetime, audio delivery, session states, and the environment-command allowlist classified by return-value portability. "Designed for the helper" must be an artifact, not an assertion.

## Consequences

- The project takes a hard dependency on an active Apple Developer Program membership ($99/yr, bus-factor 1). Signatures survive certificate expiry (secure timestamps) but not revocation; revocation recovery = re-sign and re-release.
- Verification/negative-path tests need hostile fixtures (unsigned, wrong-team, tampered dylibs); CI generates a throwaway signing identity to produce them. No content files are ever fixtures.
- Local development differs from release (Hardened Runtime, no `get-task-allow`): a documented self-sign dev path is required — it also serves the licence-transparency stance above.
- The no-sale constraint from bundled non-commercial cores is permanent for any distribution containing them. Monetization, if ever, would require unbundling.
- Rejecting `RETRO_HW_RENDER_INTERFACE` cores (Phase 1) composes cleanly: the bundled set simply excludes them until Phase 4.
- Revisit the runtime-download design (option 2's machinery) only when core count or update cadence forces it — roughly core #5 — and amend this ADR then.
