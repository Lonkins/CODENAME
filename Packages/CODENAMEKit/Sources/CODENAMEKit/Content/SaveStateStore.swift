import Foundation

/// Numbered save-state slots, path derived by convention (ADR 0004: stored
/// refs can orphan; a directory layout cannot).
public struct SaveStateStore {
  public let directory: URL

  public init(directory: URL = AppPaths.base.appendingPathComponent("SaveStates")) {
    self.directory = directory
  }

  public func load(coreName: String, contentName: String, slot: Int) -> [UInt8]? {
    guard let data = try? Data(contentsOf: url(coreName, contentName, slot)) else { return nil }
    return [UInt8](data)
  }

  public func save(_ bytes: [UInt8], coreName: String, contentName: String, slot: Int) throws {
    let target = url(coreName, contentName, slot)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes).write(to: target, options: .atomic)
  }

  public func occupiedSlots(coreName: String, contentName: String, limit: Int = 3) -> [Int] {
    (1...limit).filter {
      FileManager.default.fileExists(atPath: url(coreName, contentName, $0).path)
    }
  }

  private func url(_ coreName: String, _ contentName: String, _ slot: Int) -> URL {
    directory
      .appendingPathComponent(coreName, isDirectory: true)
      .appendingPathComponent(contentName, isDirectory: true)
      .appendingPathComponent("slot\(slot).state")
  }
}
