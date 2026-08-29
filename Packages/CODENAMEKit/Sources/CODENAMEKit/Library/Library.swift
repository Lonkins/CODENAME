import Foundation

/// ADR 0004: one Codable library; scanned entries inherit their source's
/// bookmark, File→Open singles carry their own.
public struct LibrarySource: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var bookmark: Data
  public var name: String

  public init(id: UUID, bookmark: Data, name: String) {
    self.id = id
    self.bookmark = bookmark
    self.name = name
  }
}

public struct GameEntry: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var sourceID: UUID?
  public var relativePath: String
  public var bookmark: Data?
  public var displayName: String
  public var coreID: String
  public var addedAt: Date
  public var lastPlayedAt: Date?

  public init(
    id: UUID, sourceID: UUID?, relativePath: String, bookmark: Data?, displayName: String,
    coreID: String, addedAt: Date, lastPlayedAt: Date?
  ) {
    self.id = id
    self.sourceID = sourceID
    self.relativePath = relativePath
    self.bookmark = bookmark
    self.displayName = displayName
    self.coreID = coreID
    self.addedAt = addedAt
    self.lastPlayedAt = lastPlayedAt
  }
}

public struct Library: Codable, Equatable, Sendable {
  public var sources: [LibrarySource]
  public var entries: [GameEntry]

  public init(sources: [LibrarySource] = [], entries: [GameEntry] = []) {
    self.sources = sources
    self.entries = entries
  }
}

/// One Library.json, atomic full-file writes (ADR 0004 scale ceiling noted there).
public struct LibraryStore {
  public let directory: URL

  public init(directory: URL = AppPaths.base) {
    self.directory = directory
  }

  private var fileURL: URL { directory.appendingPathComponent("Library.json") }

  public func load() -> Library {
    guard let data = try? Data(contentsOf: fileURL),
      let library = try? JSONDecoder().decode(Library.self, from: data)
    else { return Library() }
    return library
  }

  public func save(_ library: Library) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(library).write(to: fileURL, options: .atomic)
  }
}

/// Main-actor library state; saves synchronously on mutation (safe because
/// rendering lives on the core thread — ADR 0005's isolation dividend).
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var library: Library
  private let store: LibraryStore

  public init(store: LibraryStore = LibraryStore()) {
    self.store = store
    library = store.load()
  }

  /// Upserts by (coreID, path) and stamps lastPlayedAt (injectable for tests).
  public func recordPlay(
    path: String, displayName: String, coreID: String, bookmark: Data?, at date: Date = Date()
  ) {
    if let index = library.entries.firstIndex(where: {
      $0.coreID == coreID && $0.relativePath == path
    }) {
      library.entries[index].lastPlayedAt = date
      if let bookmark {
        library.entries[index].bookmark = bookmark
      }
    } else {
      library.entries.append(
        GameEntry(
          id: UUID(), sourceID: nil, relativePath: path, bookmark: bookmark,
          displayName: displayName, coreID: coreID, addedAt: date, lastPlayedAt: date))
    }
    persist()
  }

  @discardableResult
  public func addSource(bookmark: Data, name: String) -> LibrarySource {
    let source = LibrarySource(id: UUID(), bookmark: bookmark, name: name)
    library.sources.append(source)
    persist()
    return source
  }

  /// Replaces a source's entries with a fresh scan, preserving play history
  /// by relative path; File→Open singles (sourceID nil) are untouched.
  public func applyScan(
    sourceID: UUID, games: [ScannedGame], coreIDFor: (String) -> String?
  ) {
    let previous = library.entries.filter { $0.sourceID == sourceID }
    library.entries.removeAll { $0.sourceID == sourceID }
    for game in games {
      guard let coreID = coreIDFor(game.ext) else { continue }
      let existing = previous.first { $0.relativePath == game.relativePath }
      library.entries.append(
        GameEntry(
          id: existing?.id ?? UUID(), sourceID: sourceID, relativePath: game.relativePath,
          bookmark: nil, displayName: game.displayName, coreID: coreID,
          addedAt: existing?.addedAt ?? Date(), lastPlayedAt: existing?.lastPlayedAt))
    }
    persist()
  }

  public func recents(limit: Int) -> [GameEntry] {
    library.entries
      .filter { $0.lastPlayedAt != nil }
      .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
      .prefix(limit)
      .map { $0 }
  }

  private func persist() {
    do {
      try store.save(library)
    } catch {
      // Log-hygiene: no content names.
      NSLog("library save failed: \(error.localizedDescription)")
    }
  }
}
