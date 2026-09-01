import Foundation

/// Numbered save-state slots, path derived by convention from the library
/// entry (ADR 0004: stored refs can orphan; a directory layout cannot, and
/// the entry id is what makes two dumps of the same name distinct).
public struct SaveStateStore {
  public let directory: URL

  public init(directory: URL = AppPaths.saveStates) {
    self.directory = directory
  }

  public func load(entryID: UUID, slot: Int) -> [UInt8]? {
    guard let data = try? Data(contentsOf: url(entryID, slot)) else { return nil }
    return [UInt8](data)
  }

  public func save(_ bytes: [UInt8], entryID: UUID, slot: Int) throws {
    let target = url(entryID, slot)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes).write(to: target, options: .atomic)
  }

  public func occupiedSlots(entryID: UUID, limit: Int = 3) -> [Int] {
    (1...limit).filter { FileManager.default.fileExists(atPath: url(entryID, $0).path) }
  }

  private func url(_ entryID: UUID, _ slot: Int) -> URL {
    directory
      .appendingPathComponent(entryID.uuidString, isDirectory: true)
      .appendingPathComponent("slot\(slot).state")
  }
}
