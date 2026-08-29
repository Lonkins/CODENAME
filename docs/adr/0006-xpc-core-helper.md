# ADR 0006: Out-of-process core helper

- Status: Accepted (design; implementation is incremental and may pause)
- Date: 2026-08-30

## Context

ADR 0001 defers unauthenticated (user-supplied) cores and JIT to an
out-of-process helper and forbids weakening entitlements on the main app,
permanently. The transport contract (docs/transport-contract.md) fixed the
boundary shapes. This ADR settles the helper's concrete design and the
honest build order.

## Decisions

1. **Process shape.** A bundled XPC service (`Contents/XPCServices/CoreHost.xpc`),
   one core session per helper instance, launched on demand and torn down
   with the session. The app's `make-app.sh` already assembles and signs
   nested XPC services (Sparkle's), so no Xcode is required.
2. **Protocol.** An `@objc` protocol over `NSXPCConnection` — payloads must be
   ObjC-bridgeable or `NSSecureCoding`. Swift value types (`VideoFrame`,
   `CoreAVInfo`) do not cross as-is; the wire types are explicit
   `NSSecureCoding` wrappers plus `IOSurface` (which is `NSSecureCoding`) for
   frames. The interface allowlists concrete classes; a negative test proves
   unexpected classes are rejected.
3. **Transport.** Frames: IOSurface handoff (zero-copy, WebKit/OpenEmu
   precedent). Audio: shared-memory relocation of the existing SPSC ring.
   Control (load, run cadence, input snapshots, save data): XPC messages.
   The pacing clock stays app-side (ADR 0003); deadline misses re-present.
4. **Environment.** The helper implements its own environment handler —
   Class B commands (retained directory strings) name helper-local paths;
   files arrive as security-scoped URLs/descriptors at session start
   (helper containers are separate). Same allowlist policy on both sides.
5. **Entitlements.** The helper alone carries
   `com.apple.security.cs.disable-library-validation` (and, only when a
   dynarec core is actually scheduled, `allow-jit` — nothing tonight), plus
   its own tight sandbox: no network, no user-selected file access. The main
   app's entitlement set is unchanged; the ADR 0001 invariant stands. Under
   today's unsigned distribution the helper runs without hardened runtime
   (ad-hoc + library validation is the logged dyld-kill pitfall); the design
   hardens for free when signing resumes.
6. **Verification strategy.** Everything mergeable is proven with
   **anonymous-listener loopback** (`NSXPCListener.anonymous()` +
   `NSXPCConnection(listenerEndpoint:)`): same serialization machinery, no
   launchd, deterministic in CI, and excluded from the TSAN pass (libxpc
   noise is not ours). launchd-hosted smoke checks live in a non-required
   workflow so an environmental failure can never block main.

## Build order (each lands only with its verification)

A. Wire protocol + loopback service backed by the existing in-process
   `CoreSession`; loopback + IOSurface round-trip + class-allowlist tests.
B. Bundle assembly + signing in `make-app.sh`; `--xpc-smoke` launch check in
   a non-required workflow.
C. Helper-owned environment + shared-memory audio; conformance runner gains
   `--helper` and must produce **hash parity** with the recorded in-process
   digests for both real cores.
D. User-supplied core flow, helper-only, with precise rejection copy when
   the helper is unavailable.

Stopping after any step leaves main releasable.

## Consequences

- Two environment implementations sharing one policy table — accepted; the
  transport contract is the sync point.
- Helper crash becomes a recoverable "session died" (the fallible session
  lifecycle from ADR 0001 finally earns its keep).
- `dlclose` statics cease to matter for user cores: one helper per session.
