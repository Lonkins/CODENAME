#!/bin/bash
# Replays the golden hashes in Scripts/conformance-hashes.txt through the
# conformance runner, in-process AND via the XPC helper path — both must
# reproduce the recorded framebuffer hash exactly. This is the pre-release
# behavioral gate for the curated cores (docs/RELEASING.md).
#
# Content is user-supplied and local-only: each row names an env var that
# points at the content file; unset rows skip cleanly so the script runs
# anywhere without shipping or naming content.
set -euo pipefail
cd "$(dirname "$0")/.."

RUNNER="${CONFORMANCE_RUNNER:-Packages/CODENAMEKit/.build/arm64-apple-macosx/debug/conformance-runner}"
CORE_DIR="${CONFORMANCE_CORE_DIR:-build/cores}"

if [ ! -x "$RUNNER" ]; then
  echo "error: conformance-runner not built at $RUNNER" >&2
  echo "  build it: swift build --package-path Packages/CODENAMEKit --product conformance-runner" >&2
  exit 1
fi

pass=0
skip=0
fail=0
while read -r system dylib env_name frames hash; do
  case "$system" in "" | \#*) continue ;; esac
  content="${!env_name:-}"
  if [ -z "$content" ]; then
    echo "SKIP $system ($env_name unset)"
    skip=$((skip + 1))
    continue
  fi
  if [ ! -f "$CORE_DIR/$dylib" ]; then
    echo "FAIL $system ($dylib missing from $CORE_DIR — run Scripts/build-cores.sh)"
    fail=$((fail + 1))
    continue
  fi
  ok=1
  for mode in in-process helper; do
    flag=""
    [ "$mode" = helper ] && flag="--helper"
    if ! "$RUNNER" --core "$CORE_DIR/$dylib" --content "$content" \
      --frames "$frames" --expected-hash "$hash" $flag >/dev/null 2>&1; then
      echo "FAIL $system ($mode)"
      ok=0
    fi
  done
  if [ "$ok" = 1 ]; then
    echo "PASS $system (in-process + helper)"
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
done <Scripts/conformance-hashes.txt

echo "conformance: $pass passed, $skip skipped, $fail failed"
[ "$fail" = 0 ]
