# Core host transport contract

Phase 1 exit artifact required by ADR 0001: the boundary between the app and
a running core, written down so the Phase ≥2 out-of-process helper is a
implementation of this contract rather than a rediscovery of it.

## Session lifecycle

States: `created → loaded → running ⇄ (save/load state) → stopped`.

- Exactly one session exists at a time (enforced at the app layer per ADR
  0005; `CoreSession.alreadyActive` is the backstop).
- Every session method can fail; consumers treat "session died" as a
  recoverable event (window closes, library remains). In-process this only
  occurs via explicit `stop()`; out-of-process it additionally occurs on
  helper crash — call sites already route through fallible paths.
- Teardown order is load-bearing: presentation clock stops first, then audio
  output, then core shutdown (`retro_unload_game`, `retro_deinit`,
  `dlclose`), then the hosting thread exits.

## Video

- The core's framebuffer pointer is valid only inside the video-refresh
  callback. The host copies the frame (bytes, width, height, pitch, pixel
  format) before returning. **No core pointer survives the callback.**
- Delivery to the presenter is by value (`CoreSession.VideoFrame`); the
  presenter uploads to a texture it owns. Out-of-process, the copy target
  becomes an IOSurface-backed buffer — same lifetime rule, different
  destination; the presenter is unchanged.
- Duplicate frames (`NULL` data with `GET_CAN_DUPE` advertised) re-present
  the previous copy.

## Audio

- Core audio is drained from the session as owned sample arrays and written
  into a lock-free SPSC ring. The render thread reads the ring through the
  resampler; neither side allocates or locks. Out-of-process, the ring's
  storage relocates to shared memory; both APIs are already
  pointer-free at the call boundary.

## Input

- One atomic bitmask (`InputState`) is written by input sources and read by
  the core's input callback. It is a value snapshot per query — trivially
  shared-memory-able.

## Save data

- Save states and SRAM cross the boundary only as owned byte arrays
  (`serialize()/unserialize()`, `saveRAMSnapshot()/restoreSaveRAM()`).
  `retro_get_memory_data`'s live pointer is consumed inside the session and
  never exposed — the single most common cause of forced out-of-process
  redesigns, closed by construction.

## Environment command allowlist, classified by portability

Class A — value results, transport-neutral (marshal as-is over XPC):
`GET_CAN_DUPE`, `SET_PIXEL_FORMAT`, `SET_PERFORMANCE_LEVEL`,
`SET_VARIABLES` (accepted, unstored), `SET_HW_RENDER` (refused + flagged).

Class B — results the core retains for the process lifetime (each side must
own stable storage; the helper implements these locally and never proxies
them): `GET_SYSTEM_DIRECTORY`, `GET_SAVE_DIRECTORY` — C strings that must
stay valid as long as the core is loaded. Out-of-process these name
*helper-local* paths handed over as security-scoped URLs/descriptors at
session start (helper containers are separate; ADR 0001 amendment).

Class C — function-pointer results, never proxyable:
`GET_LOG_INTERFACE` (declined today; a helper may implement it locally).

Unknown commands: refused and counted, never guessed at — identical policy
on both sides of any future boundary.

## Pacing

- The presentation clock (display link) drives `retro_run`; N vblanks per
  core frame from `FramePacer.mode`, audio drift absorbed by dynamic rate
  control from ring occupancy (ADR 0003). Out-of-process, the clock stays
  app-side and run requests cross the boundary; the deadline-miss policy
  (re-present last frame, never queue) is unchanged.
