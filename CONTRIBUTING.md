# Contributing to CODENAME

Thanks for your interest. This document is short and binding.

## Ground rules

- **Scope.** CODENAME is a preservation and research tool. Contributions (code, docs, issues) must not include ROMs, BIOS files, firmware, decryption keys, or guidance on acquiring any of them. PRs containing such material are closed without review.
- **Platform.** arm64 only, macOS 15.0+, Swift 6 with strict concurrency. No Intel paths, no universal binaries.
- **Dependencies.** Every new dependency must be named and justified in the PR description, and recorded with its licence in [THIRD_PARTY.md](THIRD_PARTY.md). The bar is high; most PRs need none.

## Developer Certificate of Origin (DCO)

All commits must be signed off, certifying the [Developer Certificate of Origin 1.1](https://developercertificate.org/):

```
git commit -s
```

This adds a `Signed-off-by: Your Name <you@example.com>` trailer. By signing off you certify you have the right to submit the work under this project's licence. PRs with unsigned commits will not be merged.

## Third-party code provenance

Do not import code from any source without checking its licence first. If you adapt or vendor third-party code:

1. Confirm the licence is GPL-3.0-or-later compatible.
2. Preserve the original copyright and licence notices.
3. Record the origin, version, and licence in [THIRD_PARTY.md](THIRD_PARTY.md).
4. State the provenance in your PR description.

## Commits and PRs

- Conventional commit messages: `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`, `refactor:`, `perf:`.
- Small, focused commits; one concern per PR. PRs should be self-contained and not depend on unmerged work.
- Tests come with the change. New logic lands test-first where practical; CI must be green.
- Architectural decisions with more than one defensible answer go in `docs/adr/` as a numbered ADR.

## Building

- Requires an Apple Silicon Mac. Logic packages build with `swift build` / `swift test` (Command Line Tools sufficient); the app target requires Xcode.

## Licence

By contributing you agree your contributions are licensed under [GPL-3.0-or-later](LICENSE).
