import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SaveMigrationTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("migrate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private var states: URL { root.appendingPathComponent("SaveStates", isDirectory: true) }
  private var saves: URL { root.appendingPathComponent("Saves", isDirectory: true) }

  private func writeOldSaveRAM(core: String, content: String, _ bytes: [UInt8]) throws {
    let directory = saves.appendingPathComponent(core, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(bytes).write(to: directory.appendingPathComponent(content + ".srm"))
  }

  private func writeOldState(core: String, content: String, slot: Int, _ bytes: [UInt8]) throws {
    let directory =
      states
      .appendingPathComponent(core, isDirectory: true)
      .appendingPathComponent(content, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(bytes).write(to: directory.appendingPathComponent("slot\(slot).state"))
  }

  private func entry(_ id: UUID, path: String, core: String) -> GameEntry {
    GameEntry(
      id: id, sourceID: UUID(), relativePath: path, bookmark: nil,
      displayName: path, coreID: core, addedAt: Date(), lastPlayedAt: nil)
  }

  @Test func movesSavesToTheirEntryDirectory() throws {
    let id = UUID()
    try writeOldSaveRAM(core: "genesis", content: "Sonic", [1, 2, 3])
    try writeOldState(core: "genesis", content: "Sonic", slot: 2, [4, 5])

    let report = SaveMigration.run(
      entries: [entry(id, path: "md/Sonic.md", core: "genesis")], statesRoot: states,
      savesRoot: saves)

    #expect(report.migratedEntries == 1)
    #expect(SaveRAMStore(directory: states).load(entryID: id) == [1, 2, 3])
    #expect(SaveStateStore(directory: states).load(entryID: id, slot: 2) == [4, 5])
  }

  @Test func leavesTheOldFilesWhereTheyAre() throws {
    let id = UUID()
    try writeOldSaveRAM(core: "genesis", content: "Sonic", [1])
    _ = SaveMigration.run(
      entries: [entry(id, path: "Sonic.md", core: "genesis")], statesRoot: states,
      savesRoot: saves)
    #expect(
      FileManager.default.fileExists(
        atPath: saves.appendingPathComponent("genesis/Sonic.srm").path))
  }

  @Test func collidingEntriesEachGetACopy() throws {
    // Two dumps that shared one save under the old scheme: nothing on disk
    // says whose it was, so both inherit it rather than one silently winning.
    let usa = UUID()
    let europe = UUID()
    try writeOldSaveRAM(core: "genesis", content: "Sonic", [42])

    let report = SaveMigration.run(
      entries: [
        entry(usa, path: "usa/Sonic.md", core: "genesis"),
        entry(europe, path: "eur/Sonic.md", core: "genesis"),
      ], statesRoot: states, savesRoot: saves)

    #expect(report.migratedEntries == 2)
    #expect(SaveRAMStore(directory: states).load(entryID: usa) == [42])
    #expect(SaveRAMStore(directory: states).load(entryID: europe) == [42])
  }

  @Test func runsOnceAndNeverOverwritesNewerSaves() throws {
    let id = UUID()
    try writeOldSaveRAM(core: "genesis", content: "Sonic", [1])
    let entries = [entry(id, path: "Sonic.md", core: "genesis")]
    _ = SaveMigration.run(entries: entries, statesRoot: states, savesRoot: saves)

    // The player keeps playing; the new location moves on.
    try SaveRAMStore(directory: states).save([2, 2], entryID: id)
    let second = SaveMigration.run(entries: entries, statesRoot: states, savesRoot: saves)

    #expect(second.migratedEntries == 0)
    #expect(SaveRAMStore(directory: states).load(entryID: id) == [2, 2])
  }

  @Test func anEntryWithNothingToMigrateIsNotCounted() throws {
    let report = SaveMigration.run(
      entries: [entry(UUID(), path: "Never Played.md", core: "genesis")], statesRoot: states,
      savesRoot: saves)
    #expect(report.migratedEntries == 0)
  }
}
