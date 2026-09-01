import Foundation

/// Application Support layout — the single source for host-owned directories.
public enum AppPaths {
  public static var base: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CODENAME", isDirectory: true)
  }

  public static var system: URL { base.appendingPathComponent("System", isDirectory: true) }
  /// Handed to cores as their save directory; ours live in `saveStates`.
  public static var saves: URL { base.appendingPathComponent("Saves", isDirectory: true) }
  /// One directory per library entry, holding its battery save and slots
  /// (ADR 0004).
  public static var saveStates: URL {
    base.appendingPathComponent("SaveStates", isDirectory: true)
  }
  public static var mappings: URL { base.appendingPathComponent("Mappings", isDirectory: true) }
  public static var options: URL { base.appendingPathComponent("Options", isDirectory: true) }

  /// The option-selection file for a core, named after the core the way the
  /// per-core mapping files are.
  public static func optionsFile(forCore coreURL: URL) -> URL {
    options.appendingPathComponent(coreURL.deletingPathExtension().lastPathComponent + ".json")
  }

  /// Creates the standard directories; safe to call repeatedly.
  public static func ensureExists() {
    for url in [system, saves, mappings, options] {
      try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
}
