#!/bin/bash
# Builds the curated Phase 1 cores from pinned upstream commits (ADR 0001:
# provenance = public source + pinned SHA, built in our own environment).
# Output: build/cores/*.dylib. Bump the SHAs deliberately, never implicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

GENESIS_REPO="https://github.com/libretro/Genesis-Plus-GX"
GENESIS_SHA="a7985a9c4278ac352f8ca7bb4d3cc6b36e9e3e7d"
SNES9X_REPO="https://github.com/libretro/snes9x"
SNES9X_SHA="890b5d445538fe790aa3add3d5702c80f551e0ae"
MGBA_REPO="https://github.com/libretro/mgba"
MGBA_SHA="e31759b24e7a4e3899285ff720d7b573ac328ae7"

WORK="build/cores-src"
OUT="build/cores"
mkdir -p "$WORK" "$OUT"

fetch() { # $1 repo url, $2 sha, $3 dir
  if [ ! -d "$3/.git" ]; then
    git init -q "$3"
    git -C "$3" remote add origin "$1"
  fi
  git -C "$3" fetch -q --depth 1 origin "$2"
  git -C "$3" checkout -q FETCH_HEAD
}

echo "building genesis_plus_gx @ ${GENESIS_SHA:0:7}"
fetch "$GENESIS_REPO" "$GENESIS_SHA" "$WORK/genesis"
make -C "$WORK/genesis" -f Makefile.libretro -j"$(sysctl -n hw.ncpu)" >/dev/null
cp "$WORK/genesis/genesis_plus_gx_libretro.dylib" "$OUT/"

echo "building snes9x @ ${SNES9X_SHA:0:7}"
fetch "$SNES9X_REPO" "$SNES9X_SHA" "$WORK/snes9x"
make -C "$WORK/snes9x/libretro" -j"$(sysctl -n hw.ncpu)" >/dev/null
cp "$WORK/snes9x/libretro/snes9x_libretro.dylib" "$OUT/"

if command -v cmake >/dev/null 2>&1; then
  echo "building mgba @ ${MGBA_SHA:0:7}"
  fetch "$MGBA_REPO" "$MGBA_SHA" "$WORK/mgba"
  cmake -S "$WORK/mgba" -B "$WORK/mgba/build" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF >/dev/null
  cmake --build "$WORK/mgba/build" -j"$(sysctl -n hw.ncpu)" >/dev/null
  cp "$WORK/mgba/build/mgba_libretro.dylib" "$OUT/"
else
  echo "cmake not found; skipping mgba (CI builds it)" >&2
fi

for dylib in "$OUT"/*.dylib; do
  file "$dylib" | grep -q arm64 || { echo "error: $dylib not arm64" >&2; exit 1; }
done
ls -la "$OUT"
