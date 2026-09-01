import Foundation

/// Persists core save RAM beside that entry's save states (ADR 0004): one
/// directory per library entry holds everything derived from it, so two
/// dumps that share a filename no longer share a battery save, and deleting
/// an entry can take its saves with it.
public struct SaveRAMStore {
  public let directory: URL

  public init(directory: URL = AppPaths.saveStates) {
    self.directory = directory
  }

  public func load(entryID: UUID) -> [UInt8]? {
    guard let data = try? Data(contentsOf: url(entryID)) else { return nil }
    return [UInt8](data)
  }

  public func save(_ bytes: [UInt8], entryID: UUID) throws {
    let target = url(entryID)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes).write(to: target, options: .atomic)
  }

  private func url(_ entryID: UUID) -> URL {
    directory
      .appendingPathComponent(entryID.uuidString, isDirectory: true)
      .appendingPathComponent("save.srm")
  }
}
