import Foundation

/// Carries saves written under the old filename-derived layout into the
/// per-entry layout ADR 0004 specifies.
///
/// It copies rather than moves, and never touches the old files. Under the
/// old scheme several library entries could share one save — two dumps whose
/// files happen to have the same name — and nothing on disk records whose it
/// was, so every claimant gets a copy and the player decides. Anything the
/// library does not know about (a save whose game was removed, or a file a
/// core wrote itself) is left exactly where it is.
public enum SaveMigration {
  public struct Report: Equatable, Sendable {
    public let migratedEntries: Int
  }

  @discardableResult
  public static func run(
    entries: [GameEntry], statesRoot: URL = AppPaths.saveStates,
    savesRoot: URL = AppPaths.saves
  ) -> Report {
    var migrated = 0
    for entry in entries where migrate(entry, statesRoot: statesRoot, savesRoot: savesRoot) {
      migrated += 1
    }
    return Report(migratedEntries: migrated)
  }

  /// The old key: the core's filename and the content's, both without
  /// extension — exactly what the display loops used to derive.
  private static func oldKey(for entry: GameEntry) -> (core: String, content: String) {
    let name = (entry.relativePath as NSString).lastPathComponent
    return (entry.coreID, (name as NSString).deletingPathExtension)
  }

  private static func migrate(_ entry: GameEntry, statesRoot: URL, savesRoot: URL) -> Bool {
    let key = oldKey(for: entry)
    let destination = statesRoot.appendingPathComponent(entry.uuidDirectoryName, isDirectory: true)
    var moved = false

    let oldSaveRAM =
      savesRoot
      .appendingPathComponent(key.core, isDirectory: true)
      .appendingPathComponent(key.content + ".srm")
    moved = copy(oldSaveRAM, to: destination.appendingPathComponent("save.srm")) || moved

    let oldStates =
      statesRoot
      .appendingPathComponent(key.core, isDirectory: true)
      .appendingPathComponent(key.content, isDirectory: true)
    for slot in 1...3 {
      let source = oldStates.appendingPathComponent("slot\(slot).state")
      moved = copy(source, to: destination.appendingPathComponent("slot\(slot).state")) || moved
    }
    return moved
  }

  /// Copies only when the source exists and the destination does not: a save
  /// written since the migration first ran is newer than anything the old
  /// layout holds, and must never be overwritten by it.
  private static func copy(_ source: URL, to destination: URL) -> Bool {
    let manager = FileManager.default
    guard manager.fileExists(atPath: source.path),
      !manager.fileExists(atPath: destination.path)
    else { return false }
    do {
      try manager.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try manager.copyItem(at: source, to: destination)
      return true
    } catch {
      return false
    }
  }
}

extension GameEntry {
  fileprivate var uuidDirectoryName: String { id.uuidString }
}
