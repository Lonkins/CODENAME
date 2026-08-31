# Releasing

Releases are produced by `.github/workflows/release.yml` on any `v*` tag:

```
git tag vX.Y.Z && git push origin vX.Y.Z
```

## Pre-tag gate

Before pushing a tag, on a machine with local test content:

1. `Scripts/build-cores.sh` — fresh cores from the pinned SHAs.
2. `swift build --package-path Packages/CODENAMEKit --product conformance-runner`
3. `Scripts/conformance.sh` with the `CONFORMANCE_*` env vars set (see
   `Scripts/conformance-hashes.txt`) — every row must PASS in both modes. A
   skipped row fails the script, because a gate that skipped everything
   passes while verifying nothing; `CONFORMANCE_ALLOW_SKIP=1` is the
   deliberate escape hatch for a partial spot check. A hash mismatch means
   behavior changed: understand it before releasing, and re-record goldens
   only for a deliberate core bump.

The tag itself now runs build, test and lint before anything is packaged, so
a red commit produces no release. Conformance stays a local pre-tag step:
it needs content that never enters CI.

Publishing a release publishes to the Sparkle appcast **only when the build
is signed** — an unsigned dry run produces a prerelease and leaves the stable
feed alone, so existing installs are never offered a build that cannot pass
Gatekeeper.

The workflow builds `CODENAME.app` (arm64, sandboxed), signs it with Developer ID, notarizes and staples the app and the `.dmg`, and attaches `CODENAME-X.Y.Z.dmg` + a SHA-256 checksum to a GitHub release. All logic lives in `Scripts/make-release.sh`, which is runnable locally.

## Dry-run mode (current default)

If the signing secrets below are **absent**, the same tag still produces a release, marked `prerelease`, containing an **ad-hoc signed** dmg: not notarized, not Gatekeeper-clean. **This is the deliberate current mode**: distribution is GitHub Releases with documented manual install (see the README), and paid signing is deferred until the project warrants it. Configuring the secrets flips subsequent tags to real notarized releases with no workflow change.

## Required Actions secrets

| Secret | Contents |
|--------|----------|
| `MACOS_CERT_P12_BASE64` | Developer ID Application certificate + private key, exported as `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Password chosen when exporting the `.p12` |
| `ASC_PRIVATE_KEY_P8` | App Store Connect API private key — full contents of the downloaded `.p8` file |
| `ASC_KEY_ID` | Key ID of that API key |
| `ASC_ISSUER_ID` | Issuer ID shown on the App Store Connect keys page |

## One-time setup

1. Join the Apple Developer Program (paid membership; the notarization service requires it).
2. In Xcode or via [developer.apple.com](https://developer.apple.com/account/resources/certificates/list), create a **Developer ID Application** certificate. Export certificate + private key from Keychain Access as `.p12` with a password → first two secrets.
3. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api), create a **Team key** with Developer access. Download the `.p8` (single download!) and note the Key ID and Issuer ID → last three secrets.

## Verifying a release

On a clean Mac (or after `xattr -w com.apple.quarantine ...` to simulate download):

```
spctl --assess --type open --context context:primary-signature -v CODENAME-X.Y.Z.dmg
stapler validate /Applications/CODENAME.app
spctl --assess --type execute -v /Applications/CODENAME.app
```

All three must pass for a Gatekeeper-clean release.

## Local release build (maintainer)

```
VERSION=0.1.0 CODESIGN_IDENTITY="Developer ID Application: <name> (<team>)" \
ASC_KEY_PATH=~/keys/asc.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=YYYY \
./Scripts/make-release.sh
```

Omit `CODESIGN_IDENTITY` for a local dry run.
