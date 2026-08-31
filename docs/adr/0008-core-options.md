# ADR 0008: Core options — which interfaces the frontend speaks

- Status: Accepted (model and environment answers; persistence and UI land in later slices)
- Date: 2026-08-31

## Context

Until now the frontend accepted a core's option declarations and discarded
them, and refused `GET_VARIABLE` outright. Cores therefore ran on whatever
their compiled-in fallbacks happened to be, and nothing the user could touch
influenced them. Every real core has settings that matter — region, BIOS use,
renderer, frame skipping, colour correction — so this is the gap between
"emulation runs" and "emulation the user can configure".

libretro has accumulated three declaration interfaces for the same idea, and
a frontend chooses which of them it speaks by the number it reports for
`GET_CORE_OPTIONS_VERSION`:

- **version 0** — `SET_VARIABLES`, an array of `{ key, "Title; a|b|c" }`.
- **version 1** — `SET_CORE_OPTIONS` / `_INTL`, structured definitions with a
  separate default and per-value labels.
- **version 2** — `SET_CORE_OPTIONS_V2` / `_V2_INTL`, adding categories.

## Decisions

1. **Report version 2, and implement all three.** The number reported is not
   a statement about which interfaces exist; it is the ceiling a core is
   allowed to use. The vendored header is explicit that a frontend "should
   strive to support" the older versions as well, and the option shims cores
   vendor call their chosen interface without inspecting the result — a core
   that picks one we ignore ends up with no options at all, silently. All
   three paths therefore parse into one internal model.

   The alternative was to report 0 and implement only `SET_VARIABLES`, which
   is spec-legal and about half the code: nearly every modern core carries a
   shim that downgrades its definitions to the v0 grammar. It was rejected
   because it discards the per-value display labels the settings UI wants,
   and because it makes correct behaviour depend on every core having a
   working downgrade path rather than on this frontend being complete.

2. **Categories are not supported, and the v2 setters say so.** Their return
   value advertises category support rather than success; options register
   either way. Returning `false` honestly is right until there is a UI with
   somewhere to put a category.

3. **Translated variants take the English definitions.** `_INTL` carries a
   `us` block and a localized one; the frontend reads `us`. Localization is
   a whole-application decision, not one to make per core option.

4. **Values a core does not offer are refused at the door.** A selection is
   accepted only for a declared key and a declared value. A stored setting
   from an older core version can then never reach a core, which is what the
   interface asks of a frontend that persists anything.

5. **The update flag clears when it is reported, not when a variable is
   read.** The header words it as "changed since the last `GET_VARIABLE`",
   but clearing on the read loses changes for cores that read a variable
   outside their update check, and every core is in practice tested against
   frontends that clear on the query. Correctness for real cores wins over
   the literal wording; this is the one deliberate departure here.

6. **Strings handed to a core are retired, never freed mid-session.** The
   interface names no moment at which a core has provably finished with a
   `const char *` it was given. Buffers whose value actually changes are set
   aside and released when the session ends; a re-declaration that changes
   nothing retires nothing, so the set stays bounded by real changes.

## Consequences

- Cores now receive their declared defaults instead of a refusal. The
  conformance gate was re-run against real content on all four bundled
  systems before and after: Mega Drive, SNES and Game Boy reproduce their
  recorded hashes exactly, in-process and through the helper.
- `CoreOptions` is owned by the core thread, like the environment handler
  that holds it. Making selections from a UI thread is a concurrency
  question that the settings slice must answer, not this one.
- Not built here, deliberately: persistence, any UI, propagation across the
  XPC boundary for helper-hosted cores, `SET_VARIABLE` (a core setting its
  own option), and `SET_CORE_OPTIONS_DISPLAY` (a visibility hint that is
  explicitly not allowed to change what `GET_VARIABLE` answers).
