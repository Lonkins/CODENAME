import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SaveStateStoreTests {
  private let store = SaveStateStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("states-\(UUID().uuidString)", isDirectory: true))
  private let game = UUID()
  private let other = UUID()

  @Test func roundTripsPerSlot() throws {
    try store.save([1, 2, 3], entryID: game, slot: 1)
    try store.save([4], entryID: game, slot: 2)
    #expect(store.load(entryID: game, slot: 1) == [1, 2, 3])
    #expect(store.load(entryID: game, slot: 2) == [4])
    #expect(store.load(entryID: game, slot: 3) == nil)
  }

  @Test func slotsAreIsolatedByEntry() throws {
    // The defect this replaces: two dumps whose files happen to share a
    // basename shared one directory, so each restored the other's state.
    try store.save([7], entryID: game, slot: 1)
    #expect(store.load(entryID: other, slot: 1) == nil)
  }

  @Test func occupiedSlotsListed() throws {
    #expect(store.occupiedSlots(entryID: game) == [])
    try store.save([1], entryID: game, slot: 3)
    try store.save([1], entryID: game, slot: 1)
    #expect(store.occupiedSlots(entryID: game) == [1, 3])
  }
}
