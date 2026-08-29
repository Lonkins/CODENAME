import Foundation

/// Application Support layout — the single source for host-owned directories.
public enum AppPaths {
  public static var base: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CODENAME", isDirectory: true)
  }

  public static var system: URL { base.appendingPathComponent("System", isDirectory: true) }
  public static var saves: URL { base.appendingPathComponent("Saves", isDirectory: true) }
  public static var mappings: URL { base.appendingPathComponent("Mappings", isDirectory: true) }

  /// Creates the standard directories; safe to call repeatedly.
  public static func ensureExists() {
    for url in [system, saves, mappings] {
      try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
}
