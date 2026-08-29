# ADR 0004: Library data model and persistence

- Status: Accepted
- Date: 2026-08-29

## Context

Phase 2 adds a game library: user-selected sources (folders) plus individually opened files, persisted across launches, expected scale well under 1,000 entries for the foreseeable future. Candidates: a single Codable JSON file, SwiftData, SQLite.

## Decision

**One `Library.json` (Codable, atomic full-file writes) in Application Support.** Two record types:

- `LibrarySource`: id, security-scoped bookmark blob, display name — one per user-granted folder.
- `GameEntry`: id, optional `sourceID` + path relative to that source, optional own bookmark (only for File→Open singles), display name, `coreID`, added/last-played dates.

Scanned entries carry **no bookmark of their own**: a folder's app-scoped bookmark already grants everything beneath it; per-game bookmarks would add kilobytes each and thousands of re-resolutions for nothing. Save-state and SRAM locations are **derived by convention** (`Application Support/CODENAME/SaveStates/<entry.id>/…`), never stored — stored refs are a second source of truth that can orphan; a directory convention cannot.

No `system` field separate from `coreID`: the mapping is 1:1 with two bundled cores; a systems table is speculative until one core serves several systems.

Rejected: **SwiftData** (model classes, ModelContainer main-actor coupling, migration machinery, and strict-concurrency friction for one flat array with no queries), **SQLite** (buys partial writes and indexes a tens-of-KB in-memory array does not need). JSON is also deliberately user-serviceable in a pre-alpha: readable, attachable to a bug report, deletable to reset.

State lives in one `@MainActor @Observable LibraryModel` saving synchronously on mutation — safe because rendering happens on the core thread, so a main-thread write can never touch frame pacing (ADR 0005).

Model, store, and bookmark machinery live in `CODENAMEKit` (CI-tested); only SwiftUI views live in the app target.

## Ceiling

Full-file rewrite + whole-library-in-memory holds to roughly 10k entries. The upgrade trigger is metadata/cover art or search (Phase 3+); migration is a one-time import from the same Codable types.
