import Foundation

public struct ScannedGame: Equatable, Sendable {
  public let relativePath: String
  public let displayName: String
  public let ext: String

  public init(relativePath: String, displayName: String, ext: String) {
    self.relativePath = relativePath
    self.displayName = displayName
    self.ext = ext
  }
}

/// Recursive content scan of a granted source folder. Symlinks are skipped
/// entirely (ADR 0001 amendment: containment correctness, loop avoidance);
/// hidden files skipped; matching is by extension only — routing is a hint,
/// the core is the arbiter.
public enum LibraryScanner {
  public static func scan(root: URL, extensions: Set<String>) -> [ScannedGame] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
    // Canonicalize so relative paths survive /var → /private/var and friends.
    let rootPath = root.resolvingSymlinksInPath().path
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }

    var games: [ScannedGame] = []
    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
      // The enumerator never follows directory symlinks; skipping the entry
      // itself is the whole containment rule.
      if values.isSymbolicLink == true {
        continue
      }
      guard values.isRegularFile == true else { continue }
      let ext = url.pathExtension.lowercased()
      guard extensions.contains(ext) else { continue }
      // Symlinked files were skipped above, so resolving only affects ancestors.
      let filePath = url.resolvingSymlinksInPath().path
      guard filePath.hasPrefix(rootPath + "/") else { continue }
      games.append(
        ScannedGame(
          relativePath: String(filePath.dropFirst(rootPath.count + 1)),
          displayName: url.deletingPathExtension().lastPathComponent,
          ext: ext))
    }
    return games.sorted { $0.relativePath < $1.relativePath }
  }
}
