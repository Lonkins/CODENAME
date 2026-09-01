import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct LibraryScannerTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
    let sub = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("g".utf8).write(to: root.appendingPathComponent("Sonic.md"))
    try Data("g".utf8).write(to: sub.appendingPathComponent("Mario.sfc"))
    try Data("g".utf8).write(to: root.appendingPathComponent("notes.txt"))
    try Data("g".utf8).write(to: root.appendingPathComponent(".hidden.sfc"))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link.sfc"),
      withDestinationURL: sub.appendingPathComponent("Mario.sfc"))
  }

  @Test func displayNamesAreNormalizedTitles() throws {
    try Data("g".utf8).write(to: root.appendingPathComponent("Zelda, The (USA) (Rev 1).sfc"))
    let games = LibraryScanner.scan(root: root, extensions: ["sfc"])
    #expect(games.contains { $0.displayName == "The Zelda" })
  }

  @Test func cueParserExtractsQuotedFilenames() {
    let cue = """
      FILE "Game (USA) (Track 1).bin" BINARY
        TRACK 01 MODE2/2352
      file "Game (USA) (Track 2).bin" BINARY
      REM COMMENT "not a file line"
      """
    #expect(
      LibraryScanner.cueReferencedFiles(cue) == [
        "Game (USA) (Track 1).bin", "Game (USA) (Track 2).bin",
      ])
  }

  @Test func hidesDiscTracksReferencedBySiblingCue() throws {
    let disc = root.appendingPathComponent("disc", isDirectory: true)
    try FileManager.default.createDirectory(at: disc, withIntermediateDirectories: true)
    try Data(
      """
      FILE "Crash (USA).bin" BINARY
        TRACK 01 MODE2/2352
      """.utf8
    ).write(to: disc.appendingPathComponent("Crash (USA).cue"))
    try Data("t".utf8).write(to: disc.appendingPathComponent("Crash (USA).bin"))
    try Data("g".utf8).write(to: disc.appendingPathComponent("Cartridge.bin"))

    let games = LibraryScanner.scan(root: root, extensions: ["cue", "bin"])
    let paths = games.map(\.relativePath)
    #expect(paths.contains("disc/Crash (USA).cue"))
    #expect(!paths.contains("disc/Crash (USA).bin"))
    // A .bin no cue references (a cartridge dump) still lists.
    #expect(paths.contains("disc/Cartridge.bin"))
  }

  @Test func findsMatchingFilesRecursively() {
    let games = LibraryScanner.scan(root: root, extensions: ["md", "sfc"])
    let paths = games.map(\.relativePath).sorted()
    #expect(paths == ["Sonic.md", "nested/Mario.sfc"])
    #expect(games.first { $0.relativePath == "Sonic.md" }?.displayName == "Sonic")
  }

  @Test func ignoresNonMatchingHiddenAndSymlinks() {
    let games = LibraryScanner.scan(root: root, extensions: ["md", "sfc", "txt"])
    let names = games.map(\.relativePath)
    #expect(!names.contains("link.sfc"))
    #expect(!names.contains(".hidden.sfc"))
    #expect(names.contains("notes.txt"))
  }

  @Test func emptyForMissingRoot() {
    let games = LibraryScanner.scan(
      root: root.appendingPathComponent("absent"), extensions: ["md"])
    #expect(games.isEmpty)
  }
}

@MainActor
@Suite struct LibraryModelScanTests {
  private func makeModel() -> LibraryModel {
    LibraryModel(
      store: LibraryStore(
        directory: FileManager.default.temporaryDirectory
          .appendingPathComponent("scanm-\(UUID().uuidString)", isDirectory: true)))
  }

  @Test func applyScanAddsUpdatesAndRemoves() {
    let model = makeModel()
    let source = model.addSource(bookmark: Data([1]), name: "Games")

    model.applyScan(
      sourceID: source.id,
      games: [
        ScannedGame(relativePath: "a.sfc", displayName: "a", ext: "sfc"),
        ScannedGame(relativePath: "b.md", displayName: "b", ext: "md"),
      ],
      coreIDFor: { $0 == "sfc" ? "snes9x" : "genesis" })
    #expect(model.library.entries.count == 2)

    // Mark one played, then rescan without the other.
    if let played = model.library.entries.first(where: { $0.relativePath == "a.sfc" }) {
      model.recordPlay(
        path: played.relativePath, displayName: played.displayName,
        coreID: played.coreID, bookmark: nil, at: Date(timeIntervalSince1970: 42))
    }
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "a.sfc", displayName: "a", ext: "sfc")],
      coreIDFor: { _ in "snes9x" })

    #expect(model.library.entries.count == 1)
    #expect(model.library.entries.first?.lastPlayedAt == Date(timeIntervalSince1970: 42))
  }

  @Test func scanLeavesFileOpenSinglesAlone() {
    let model = makeModel()
    model.recordPlay(path: "/solo.md", displayName: "solo", coreID: "genesis", bookmark: nil)
    let source = model.addSource(bookmark: Data([2]), name: "Folder")
    model.applyScan(sourceID: source.id, games: [], coreIDFor: { _ in nil })
    #expect(model.library.entries.count == 1)
    #expect(model.library.entries.first?.displayName == "solo")
  }

  @Test func unroutableExtensionsAreSkipped() {
    let model = makeModel()
    let source = model.addSource(bookmark: Data([3]), name: "F")
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "x.txt", displayName: "x", ext: "txt")],
      coreIDFor: { _ in nil })
    #expect(model.library.entries.isEmpty)
  }

  // MARK: - Identity across moves (what saves will be keyed on)

  @Test func movingAFileKeepsItsEntryIdentity() {
    // Saves are about to be keyed on the entry id, so a file the user drags
    // into a subfolder must keep the same entry rather than becoming a new
    // one with a fresh id and no history.
    let model = makeModel()
    let source = model.addSource(bookmark: Data([1]), name: "Games")
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "Sonic.md", displayName: "Sonic", ext: "md")],
      coreIDFor: { _ in "genesis" })
    let before = model.library.entries[0]
    model.recordPlay(
      path: "Sonic.md", displayName: "Sonic", coreID: "genesis", bookmark: nil,
      at: Date(timeIntervalSince1970: 99))

    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "genesis/Sonic.md", displayName: "Sonic", ext: "md")],
      coreIDFor: { _ in "genesis" })

    #expect(model.library.entries.count == 1)
    let after = model.library.entries[0]
    #expect(after.id == before.id)
    #expect(after.relativePath == "genesis/Sonic.md")
    #expect(after.lastPlayedAt == Date(timeIntervalSince1970: 99))
    #expect(after.addedAt == before.addedAt)
  }

  @Test func aGenuinelyNewFileGetsANewIdentity() {
    let model = makeModel()
    let source = model.addSource(bookmark: Data([1]), name: "Games")
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "Sonic.md", displayName: "Sonic", ext: "md")],
      coreIDFor: { _ in "genesis" })
    let before = model.library.entries[0].id

    model.applyScan(
      sourceID: source.id,
      games: [
        ScannedGame(relativePath: "Sonic.md", displayName: "Sonic", ext: "md"),
        ScannedGame(relativePath: "Streets.md", displayName: "Streets", ext: "md"),
      ],
      coreIDFor: { _ in "genesis" })

    let ids = model.library.entries.map(\.id)
    #expect(ids.count == 2)
    #expect(ids.contains(before))
    #expect(Set(ids).count == 2)
  }

  @Test func anAmbiguousMoveDoesNotStealAnIdentity() {
    // Two files of the same name in different folders: if one disappears and
    // another appears, there is no way to know which moved, so adopt nothing
    // rather than hand one game another's saves.
    let model = makeModel()
    let source = model.addSource(bookmark: Data([1]), name: "Games")
    model.applyScan(
      sourceID: source.id,
      games: [
        ScannedGame(relativePath: "usa/Sonic.md", displayName: "Sonic", ext: "md"),
        ScannedGame(relativePath: "eur/Sonic.md", displayName: "Sonic", ext: "md"),
      ],
      coreIDFor: { _ in "genesis" })
    let before = Set(model.library.entries.map(\.id))

    model.applyScan(
      sourceID: source.id,
      games: [
        ScannedGame(relativePath: "usa/Sonic.md", displayName: "Sonic", ext: "md"),
        ScannedGame(relativePath: "jpn/Sonic.md", displayName: "Sonic", ext: "md"),
      ],
      coreIDFor: { _ in "genesis" })

    let kept = model.library.entries.first { $0.relativePath == "usa/Sonic.md" }
    let fresh = model.library.entries.first { $0.relativePath == "jpn/Sonic.md" }
    #expect(kept != nil)
    #expect(before.contains(kept!.id))
    #expect(fresh != nil)
    #expect(!before.contains(fresh!.id))
  }

  @Test func aMoveOnlyCountsWithinTheSameCore() {
    let model = makeModel()
    let source = model.addSource(bookmark: Data([1]), name: "Games")
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "Sonic.md", displayName: "Sonic", ext: "md")],
      coreIDFor: { _ in "genesis" })
    let before = model.library.entries[0].id

    // Same base name, different extension and core: a different game.
    model.applyScan(
      sourceID: source.id,
      games: [ScannedGame(relativePath: "roms/Sonic.sfc", displayName: "Sonic", ext: "sfc")],
      coreIDFor: { _ in "snes9x" })
    #expect(model.library.entries[0].id != before)
  }
}
