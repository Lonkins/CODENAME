# Security Policy

## Reporting a vulnerability

Please report vulnerabilities privately via [GitHub Security Advisories](../../security/advisories/new). Do not open public issues for security problems.

You can expect an acknowledgement within 7 days. Coordinated disclosure preferred; we will credit reporters unless they ask otherwise.

## Scope

Of particular interest:

- The core loading path: signature verification, library validation, entitlement configuration (see `docs/adr/0001-core-loading-and-entitlements.md`).
- Sandbox and security-scoped bookmark handling.
- The release pipeline: signing, notarization, and update (Sparkle appcast) integrity.

## Supported versions

Pre-alpha: only the latest release receives fixes.
