import Foundation

/// The one place that decides what runs where. Every start path goes
/// through it, and the host is derived from where the core sits rather
/// than passed in — a caller that forgets cannot land a helper-only core
/// in this process (ADR 0001, ADR 0007).
public enum ContentRouter {
  public enum Host: Equatable, Sendable {
    case inProcess
    case helper
  }

  /// What must be in place before a session of this kind can boot.
  public enum Prerequisite: Equatable, Sendable {
    case playStationBIOS
  }

  public struct Route: Equatable, Sendable {
    public let coreURL: URL
    public let host: Host
    public let prerequisite: Prerequisite?
  }

  public enum Failure: Error, Equatable {
    case unsupported(fileExtension: String)
    case tooLarge(bytes: Int)
  }

  /// Cartridge content has hard size maxima; refuse absurd files before
  /// handing bytes to a core (ADR 0001 amendment). Cores that stream
  /// content from disk themselves are exempt.
  public static let maxCartridgeBytes = 64 * 1024 * 1024

  /// The curated core directory of the running app bundle — the only
  /// place this process may load a core from. Read from the bundle, never
  /// from a candidate core's own path.
  public static var bundledPlugInsDirectory: URL {
    Bundle.main.builtInPlugInsURL ?? URL(fileURLWithPath: "/nonexistent")
  }

  /// In-process hosting means exactly what the in-process trust policy
  /// allows: the core sits directly in the bundle's PlugIns directory.
  /// Anything else — a helper-only subdirectory, a user-supplied file
  /// anywhere on disk — runs in the helper.
  public static func host(forCore coreURL: URL, plugInsDirectory: URL) -> Host {
    let policy = CoreTrustPolicy(allowedDirectory: plugInsDirectory)
    return (try? policy.validate(coreURL)) != nil ? .inProcess : .helper
  }

  /// A core chosen directly (a user-supplied core picking its own content).
  public static func route(forCore coreURL: URL, plugInsDirectory: URL) -> Route {
    Route(
      coreURL: coreURL, host: host(forCore: coreURL, plugInsDirectory: plugInsDirectory),
      prerequisite: nil)
  }

  /// Content chosen by the user or replayed from the library.
  /// `preferredCoreID` is the library's stored core id; it selects among
  /// the cores claiming the extension and falls back when the core is gone.
  public static func route(
    contentURL: URL, preferredCoreID: String? = nil, in entries: [CoreCatalog.Entry],
    plugInsDirectory: URL, sizeInBytes: Int?
  ) throws(Failure) -> Route {
    let fileExtension = contentURL.pathExtension.lowercased()
    let candidates = entries.filter { $0.extensions.contains(fileExtension) }
    guard let core = select(from: candidates, preferredCoreID: preferredCoreID, content: contentURL)
    else { throw .unsupported(fileExtension: fileExtension) }

    if !core.needsFullPath, let sizeInBytes, sizeInBytes > maxCartridgeBytes {
      throw .tooLarge(bytes: sizeInBytes)
    }

    return Route(
      coreURL: core.url, host: host(forCore: core.url, plugInsDirectory: plugInsDirectory),
      prerequisite: prerequisite(for: core))
  }

  private static func select(
    from candidates: [CoreCatalog.Entry], preferredCoreID: String?, content: URL
  ) -> CoreCatalog.Entry? {
    if let preferredCoreID,
      let stored = candidates.first(where: {
        $0.url.deletingPathExtension().lastPathComponent == preferredCoreID
      })
    {
      return stored
    }
    guard candidates.count > 1 else { return candidates.first }
    // Disc extensions are legitimately multi-claimed (.cue is PlayStation
    // and Sega CD); the disc itself disambiguates (ADR 0007).
    let identified = DiscSniffer.identify(contentURL: content)
    return candidates.first { $0.system == identified } ?? candidates.first
  }

  private static func prerequisite(for core: CoreCatalog.Entry) -> Prerequisite? {
    core.system == .playStation ? .playStationBIOS : nil
  }
}
