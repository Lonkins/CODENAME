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

/// How an entry gets back to the file it names. Scanned entries carry no
/// bookmark of their own (ADR 0004) — the source folder's grant covers
/// them — so every path that opens content has to ask, and ask the same way.
public enum ContentResolution: Equatable, Sendable {
  case inSource(sourceID: UUID, relativePath: String)
  case ownBookmark(Data)
  case unresolvable
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
  public var displayOverrides: DisplaySettings?

  /// The source grant is preferred over a stored per-file bookmark: it
  /// outlives one, and it covers the sibling files a disc image needs.
  public static func resolution(for entry: GameEntry) -> ContentResolution {
    if let sourceID = entry.sourceID {
      return .inSource(sourceID: sourceID, relativePath: entry.relativePath)
    }
    if let bookmark = entry.bookmark {
      return .ownBookmark(bookmark)
    }
    return .unresolvable
  }

  public init(
    id: UUID, sourceID: UUID?, relativePath: String, bookmark: Data?, displayName: String,
    coreID: String, addedAt: Date, lastPlayedAt: Date?, displayOverrides: DisplaySettings? = nil
  ) {
    self.id = id
    self.sourceID = sourceID
    self.relativePath = relativePath
    self.bookmark = bookmark
    self.displayName = displayName
    self.coreID = coreID
    self.addedAt = addedAt
    self.lastPlayedAt = lastPlayedAt
    self.displayOverrides = displayOverrides
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

    let scannedPaths = Set(games.map(\.relativePath))
    // Entries whose exact path is gone may simply have moved. Only a name
    // that is unique on both sides can be adopted — with two same-named
    // files there is no way to tell which moved, and guessing would hand a
    // game another game's saves.
    let departed = previous.filter { !scannedPaths.contains($0.relativePath) }
    let arrivals = games.filter { game in
      !previous.contains { $0.relativePath == game.relativePath }
    }
    var adoptable: [String: GameEntry] = [:]
    for entry in departed {
      let name = (entry.relativePath as NSString).lastPathComponent
      let key = "\(entry.coreID)/\(name)"
      if adoptable[key] == nil
        && departed.filter({
          ($0.relativePath as NSString).lastPathComponent == name && $0.coreID == entry.coreID
        }).count == 1
      {
        adoptable[key] = entry
      }
    }

    for game in games {
      guard let coreID = coreIDFor(game.ext) else { continue }
      var existing = previous.first { $0.relativePath == game.relativePath }
      if existing == nil {
        let name = (game.relativePath as NSString).lastPathComponent
        let sameNamedArrivals = arrivals.filter {
          ($0.relativePath as NSString).lastPathComponent == name
        }
        if sameNamedArrivals.count == 1 {
          existing = adoptable.removeValue(forKey: "\(coreID)/\(name)")
        }
      }
      library.entries.append(
        GameEntry(
          id: existing?.id ?? UUID(), sourceID: sourceID, relativePath: game.relativePath,
          bookmark: nil, displayName: game.displayName, coreID: coreID,
          addedAt: existing?.addedAt ?? Date(), lastPlayedAt: existing?.lastPlayedAt))
    }
    persist()
  }

  /// Bumped when artwork changes so views depending on the model re-read it.
  public private(set) var artworkRevision = 0

  public func noteArtworkChanged() {
    artworkRevision += 1
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
