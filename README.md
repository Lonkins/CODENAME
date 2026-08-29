# CODENAME

A native Apple Silicon (arm64) macOS frontend for [libretro](https://www.libretro.com/) cores, built for game preservation and research.

Signed, notarized, and Gatekeeper-clean from the first release. Swift 6, Metal presentation, macOS 15+.

## Status

Pre-alpha. Phase 0 (foundations: CI, signing, notarization, update channel) in progress. Not yet usable.

## What this is

- A macOS-native host application that loads libretro emulator cores and presents them through Metal, with system-standard audio, input, and windowing.
- arm64 only. macOS 15.0 minimum.

## What this is not

- Not an emulator. Emulation comes from actively maintained upstream libretro cores.
- This project contains no BIOS files, ROMs, firmware, or decryption keys, and provides no guidance on acquiring them. Users supply their own legally obtained content.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) (added in Phase 0).
