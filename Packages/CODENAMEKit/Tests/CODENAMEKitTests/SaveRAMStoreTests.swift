import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SaveRAMStoreTests {
  private let store = SaveRAMStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("srm-\(UUID().uuidString)", isDirectory: true))

  @Test func roundTripsPerCoreAndContent() throws {
    try store.save([9, 8, 7], coreName: "snes9x", contentName: "Some Game")
    #expect(store.load(coreName: "snes9x", contentName: "Some Game") == [9, 8, 7])
    #expect(store.load(coreName: "genesis", contentName: "Some Game") == nil)
    #expect(store.load(coreName: "snes9x", contentName: "Other") == nil)
  }

  @Test func overwritesExistingSave() throws {
    try store.save([1], coreName: "c", contentName: "g")
    try store.save([2, 2], coreName: "c", contentName: "g")
    #expect(store.load(coreName: "c", contentName: "g") == [2, 2])
  }

  @Test func missingSaveIsNil() {
    #expect(store.load(coreName: "none", contentName: "none") == nil)
  }
}
