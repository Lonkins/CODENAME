import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SaveRAMStoreTests {
  private let store = SaveRAMStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("srm-\(UUID().uuidString)", isDirectory: true))
  private let game = UUID()
  private let other = UUID()

  @Test func roundTripsPerEntry() throws {
    try store.save([9, 8, 7], entryID: game)
    #expect(store.load(entryID: game) == [9, 8, 7])
    #expect(store.load(entryID: other) == nil)
  }

  @Test func overwritesExistingSave() throws {
    try store.save([1], entryID: game)
    try store.save([2, 2], entryID: game)
    #expect(store.load(entryID: game) == [2, 2])
  }

  @Test func missingSaveIsNil() {
    #expect(store.load(entryID: UUID()) == nil)
  }

  @Test func batterySaveSitsBesideTheStatesForTheSameGame() throws {
    // ADR 0004: one directory per library entry holds everything derived
    // from it, so deleting the entry can take its saves with it.
    try store.save([1], entryID: game)
    #expect(
      FileManager.default.fileExists(
        atPath: store.directory.appendingPathComponent(game.uuidString)
          .appendingPathComponent("save.srm").path))
  }
}
