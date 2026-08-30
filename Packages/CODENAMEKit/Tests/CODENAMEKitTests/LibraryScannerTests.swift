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
}
