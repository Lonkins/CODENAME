import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct ContentResolutionTests {
  private func entry(sourceID: UUID?, bookmark: Data?) -> GameEntry {
    GameEntry(
      id: UUID(), sourceID: sourceID, relativePath: "snes/Mario.sfc", bookmark: bookmark,
      displayName: "Mario", coreID: "snes9x_libretro", addedAt: Date(), lastPlayedAt: nil)
  }

  @Test func aScannedGameResolvesThroughItsSource() {
    // ADR 0004: scanned entries deliberately carry no bookmark of their own —
    // the folder's grant covers everything beneath it. Open Recent refused
    // exactly these, which is every game found by scanning.
    let source = UUID()
    #expect(
      GameEntry.resolution(for: entry(sourceID: source, bookmark: nil))
        == .inSource(sourceID: source, relativePath: "snes/Mario.sfc"))
  }

  @Test func aSinglyOpenedFileResolvesThroughItsOwnBookmark() {
    let bookmark = Data([1, 2, 3])
    #expect(
      GameEntry.resolution(for: entry(sourceID: nil, bookmark: bookmark))
        == .ownBookmark(bookmark))
  }

  @Test func theSourceGrantWinsWhenAnEntryHasBoth() {
    // A folder grant outlives a per-file one and covers sibling tracks, so
    // prefer it when a stale bookmark also happens to be stored.
    let source = UUID()
    #expect(
      GameEntry.resolution(for: entry(sourceID: source, bookmark: Data([1])))
        == .inSource(sourceID: source, relativePath: "snes/Mario.sfc"))
  }

  @Test func anEntryWithNeitherIsUnresolvable() {
    #expect(GameEntry.resolution(for: entry(sourceID: nil, bookmark: nil)) == .unresolvable)
  }
}
