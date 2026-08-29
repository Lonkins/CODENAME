import Foundation

/// Persists core save RAM, keyed by core and content identity (never by full
/// source path, so saves survive the user moving their content folder).
public struct SaveRAMStore {
  public let directory: URL

  public init(directory: URL = AppPaths.saves) {
    self.directory = directory
  }

  public func load(coreName: String, contentName: String) -> [UInt8]? {
    guard let data = try? Data(contentsOf: url(coreName: coreName, contentName: contentName)) else {
      return nil
    }
    return [UInt8](data)
  }

  public func save(_ bytes: [UInt8], coreName: String, contentName: String) throws {
    let target = url(coreName: coreName, contentName: contentName)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes).write(to: target, options: .atomic)
  }

  private func url(coreName: String, contentName: String) -> URL {
    directory
      .appendingPathComponent(coreName, isDirectory: true)
      .appendingPathComponent(contentName + ".srm")
  }
}
