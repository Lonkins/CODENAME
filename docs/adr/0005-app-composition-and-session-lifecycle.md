# ADR 0005: App composition and session/window lifecycle

- Status: Accepted
- Date: 2026-08-29

## Context

Phase 2 adds SwiftUI surfaces (library, settings) to an app whose game window, event loop, and menu are AppKit-owned by north-star constraint, with rendering on a dedicated core thread (ADR 0003) and a process-exclusive core session (ADR 0001). How do the surfaces coexist, and how do sessions start and stop?

## Decisions

1. **AppKit `@main` stays.** No SwiftUI App lifecycle: window creation, restoration, the hand-built menu, and Sparkle are already delegate-wired, and `WindowGroup` would take ownership of exactly what the north star reserves for AppKit.
2. **Separate windows.** Library = `NSWindow` hosting `NSHostingView` (created at launch, the app's face when idle). Game = its own `NSWindow` created per session and closed on stop — **window existence == session existence**, making the exclusivity invariant physical and keeping SwiftUI permanently out of the game window's responder chain and layer tree. Settings = a third hosting window on ⌘, (no SwiftUI `Settings` scene — it needs the SwiftUI lifecycle). Rejected: contentView-swapping one window (reconciles styleMask/title/fullscreen across modes and rebuilds the CAMetalLayer the display link is bound to on every flip).
3. **Session lifecycle.** `CoreDisplayLoop` stays one-shot and gains a synchronous `stop()` executed on the core thread (`perform(…waitUntilDone: true)`); the app constructs a fresh loop per game. Teardown order is load-bearing: invalidate display link → stop audio → `session.shutdown()` → release session/presenter/ring (drives `dlclose`) → stop the thread's run loop so it exits. `AppDelegate.startGame(entry)` calls `stopGame()` first; closing the game window stops the session. The `alreadyActive` guard remains as backstop, not mechanism.
4. **Extension→core routing asks the cores.** A `CoreCatalog` enumerates bundled plug-ins through the existing trust policy + `CoreLibrary`, reading `retro_get_system_info().valid_extensions` — authoritative and immune to pinned-SHA bumps rotting a hardcoded table. Collisions resolve deterministically (first match by sorted core filename) and the chosen `coreID` is persisted per entry so later additions cannot silently re-route existing games. Routing is a hint; the core's `retro_load_game` is the arbiter. No magic-byte sniffing — parsing untrusted content in the app process is the exposure ADR 0001's containment story exists to remove.
5. **No `CFBundleDocumentTypes` in Phase 2.** Finder integration is unrequested, and claiming `.md` (Mega Drive) would collide with Markdown system-wide. `NSOpenPanel` needs no plist entries.
6. **Isolation dividend (recorded on purpose):** with rendering on the core thread and SwiftUI in separate windows, a main-thread hitch (library save, folder scan) cannot affect frame pacing — this is what licenses ADR 0004's synchronous persistence.

## Ceiling

`dlclose` does not guarantee a core's statics reset; game A → stop → game B is the risk case. Verified manually against both bundled cores; if a core misbehaves, the honest fallbacks are relaunch-per-game or the Phase ≥2 XPC helper — not loader workarounds.

Out of scope now: pause, fast-forward, resume-on-launch, multi-window sessions.
