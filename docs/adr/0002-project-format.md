# ADR 0002: Project format — SwiftPM everywhere, no Xcode project

- Status: Accepted
- Date: 2026-08-29

## Context

The app needs a buildable target producing a signed `.app` bundle. Candidate formats: a checked-in `.xcodeproj`, a generated project (XcodeGen/Tuist), or pure SwiftPM plus a bundling script. Constraints that decide it:

- Phase 0/1 has no storyboards, no xibs, and no asset catalogs; UI is code-only (AppKit now, SwiftUI panels later — both code).
- All signing/notarization/stapling is CLI tooling (`codesign`, `notarytool`, `stapler`) regardless of project format — the release pipeline gains nothing from Xcode.
- Development must work on machines with only Command Line Tools; CI must be able to build, sign, and assemble deterministically.

## Options

1. **Checked-in `.xcodeproj`.** Standard, but `project.pbxproj` is merge-hostile, reviewable only with effort, and can only be authored/maintained from the Xcode GUI — unbuildable and unverifiable in a CLT-only environment.
2. **XcodeGen** (YAML → generated project). Reviewable manifest, but adds a build-time dependency and still requires full Xcode to build the generated project.
3. **Tuist.** Same trade as 2 with more machinery than a one-app project justifies.
4. **SwiftPM only.** The app is an `executableTarget`; a ~40-line script assembles `CODENAME.app` (binary + `Info.plist` + `PkgInfo`), signs it with entitlements, and verifies. Xcode users still get full IDE support by opening `Package.swift` directly — SwiftPM is a first-class Xcode citizen with no project file to churn.

## Decision

Option 4. `Scripts/make-app.sh` is the single app-assembly path for local builds, CI, and the release workflow; app metadata lives in `App/Info.plist` and `App/CODENAME.entitlements` as plain reviewable files. No dependency added.

arm64-only is enforced by building on arm64 hosts with no universal-binary flags anywhere; CI asserts the built slice.

## Known ceilings (revisit triggers)

- **Asset catalogs / app icon:** `actool` needs full Xcode; an `.icns` via `iconutil` (ships with macOS) covers the icon until then.
- **Metal shaders:** build-time `.metal` compilation needs the Xcode Metal toolchain. Phase 1's single blit shader compiles at runtime from source (`MTLDevice.makeLibrary(source:)`). If shader count or startup cost grows, revisit.
- **Sparkle embedding:** the script grows a copy-framework-and-rpath step when Sparkle lands.

If any ceiling is hit hard, migrating to option 2 (XcodeGen) is mechanical: targets and settings are already expressed as plain files.
