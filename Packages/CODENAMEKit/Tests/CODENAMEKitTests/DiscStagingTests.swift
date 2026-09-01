import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct DiscStagingTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private func write(_ name: String, _ contents: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try Data(contents.utf8).write(to: url)
    return url
  }

  // MARK: - What the sending side has to gather

  @Test func aCueNamesItsTracksInFileOrder() throws {
    _ = try write("Game (Track 1).bin", "one")
    _ = try write("Game (Track 2).bin", "two")
    let cue = try write(
      "Game.cue",
      """
      FILE "Game (Track 1).bin" BINARY
        TRACK 01 MODE2/2352
      FILE "Game (Track 2).bin" BINARY
        TRACK 02 AUDIO
      """)

    let handoff = try DiscStaging.prepare(contentAt: cue)
    #expect(handoff.payload.name == "Game.cue")
    #expect(handoff.payload.referencedNames == ["Game (Track 1).bin", "Game (Track 2).bin"])
    #expect(handoff.payload.cueText?.hasPrefix("FILE") == true)
    #expect(handoff.files.map(\.lastPathComponent) == handoff.payload.referencedNames)
  }

  @Test func singleFileContentIsItsOwnReference() throws {
    let disc = try write("Game.chd", "not really a chd")
    let handoff = try DiscStaging.prepare(contentAt: disc)
    #expect(handoff.payload.name == "Game.chd")
    #expect(handoff.payload.cueText == nil)
    #expect(handoff.payload.referencedNames == ["Game.chd"])
    #expect(handoff.files == [disc])
  }

  @Test func aCueNamingAMissingTrackIsRefused() throws {
    let cue = try write("Broken.cue", "FILE \"Gone.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
    #expect(throws: DiscStaging.Failure.missingTrack("Gone.bin")) {
      try DiscStaging.prepare(contentAt: cue)
    }
  }

  // MARK: - What the receiving side builds

  @Test func stagingMakesTheContentReadableThroughTheDescriptors() throws {
    // The whole point: a process that cannot open the file by path reads it
    // through descriptors the sender already opened.
    let track = try write("Game (Track 1).bin", "TRACKDATA")
    let cue = try write("Game.cue", "FILE \"Game (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\n")
    let handoff = try DiscStaging.prepare(contentAt: cue)
    let handle = try FileHandle(forReadingFrom: track)
    defer { try? handle.close() }

    let staging = root.appendingPathComponent("received", isDirectory: true)
    let staged = try DiscStaging.materialize(
      handoff.payload, descriptors: [handle.fileDescriptor], in: staging)

    #expect(staged.lastPathComponent == "Game.cue")
    let stagedCue = try String(contentsOf: staged, encoding: .utf8)
    #expect(stagedCue == handoff.payload.cueText)
    let stagedTrack = try String(
      contentsOf: staging.appendingPathComponent("Game (Track 1).bin"), encoding: .utf8)
    #expect(stagedTrack == "TRACKDATA")
  }

  @Test func singleFileStagingPointsAtTheDescriptorItself() throws {
    let disc = try write("Game.chd", "DISCDATA")
    let handoff = try DiscStaging.prepare(contentAt: disc)
    let handle = try FileHandle(forReadingFrom: disc)
    defer { try? handle.close() }

    let staging = root.appendingPathComponent("received-single", isDirectory: true)
    let staged = try DiscStaging.materialize(
      handoff.payload, descriptors: [handle.fileDescriptor], in: staging)
    #expect(staged.lastPathComponent == "Game.chd")
    #expect(try String(contentsOf: staged, encoding: .utf8) == "DISCDATA")
  }

  @Test func aDescriptorCountThatDoesNotMatchIsRefused() throws {
    let disc = try write("Game.chd", "DISCDATA")
    let handoff = try DiscStaging.prepare(contentAt: disc)
    #expect(throws: DiscStaging.Failure.descriptorCountMismatch(expected: 1, received: 0)) {
      try DiscStaging.materialize(
        handoff.payload, descriptors: [],
        in: root.appendingPathComponent("received-empty", isDirectory: true))
    }
  }
}
