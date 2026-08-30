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
      let baseName = url.deletingPathExtension().lastPathComponent
      games.append(
        ScannedGame(
          relativePath: String(filePath.dropFirst(rootPath.count + 1)),
          displayName: TitleNormalizer.normalize(filename: baseName).displayTitle,
          ext: ext))
    }
    return hidingCueTracks(games.sorted { $0.relativePath < $1.relativePath }, root: root)
  }

  /// Disc images referenced by a sibling cue sheet are tracks, not games —
  /// hide them so a disc appears once in the library (ADR 0007).
  static func hidingCueTracks(_ games: [ScannedGame], root: URL) -> [ScannedGame] {
    let maxCueBytes = 1024 * 1024
    var referenced = Set<String>()
    for game in games where game.ext == "cue" {
      let cueURL = root.appendingPathComponent(game.relativePath)
      guard
        let size = try? cueURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size <= maxCueBytes,
        let text = try? String(contentsOf: cueURL, encoding: .utf8)
      else { continue }
      let cueDirectory = (game.relativePath as NSString).deletingLastPathComponent
      for file in cueReferencedFiles(text) {
        referenced.insert(
          cueDirectory.isEmpty ? file : cueDirectory + "/" + file)
      }
    }
    guard !referenced.isEmpty else { return games }
    return games.filter { !referenced.contains($0.relativePath) }
  }

  /// Filenames named by `FILE "..." <TYPE>` lines of a cue sheet.
  static func cueReferencedFiles(_ cueText: String) -> [String] {
    cueText.split(whereSeparator: \.isNewline).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.uppercased().hasPrefix("FILE") else { return nil }
      guard let first = trimmed.firstIndex(of: "\""),
        let last = trimmed.lastIndex(of: "\""), first < last
      else { return nil }
      return String(trimmed[trimmed.index(after: first)..<last])
    }
  }
}
