import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SaveStateStoreTests {
  private let store = SaveStateStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("states-\(UUID().uuidString)", isDirectory: true))

  @Test func roundTripsPerSlot() throws {
    try store.save([1, 2, 3], coreName: "c", contentName: "g", slot: 1)
    try store.save([4], coreName: "c", contentName: "g", slot: 2)
    #expect(store.load(coreName: "c", contentName: "g", slot: 1) == [1, 2, 3])
    #expect(store.load(coreName: "c", contentName: "g", slot: 2) == [4])
    #expect(store.load(coreName: "c", contentName: "g", slot: 3) == nil)
  }

  @Test func slotsAreIsolatedByContentAndCore() throws {
    try store.save([7], coreName: "c1", contentName: "g", slot: 1)
    #expect(store.load(coreName: "c2", contentName: "g", slot: 1) == nil)
    #expect(store.load(coreName: "c1", contentName: "other", slot: 1) == nil)
  }

  @Test func occupiedSlotsListed() throws {
    #expect(store.occupiedSlots(coreName: "c", contentName: "g") == [])
    try store.save([1], coreName: "c", contentName: "g", slot: 3)
    try store.save([1], coreName: "c", contentName: "g", slot: 1)
    #expect(store.occupiedSlots(coreName: "c", contentName: "g") == [1, 3])
  }
}
