import CLibretro
import Foundation

/// What the bundled cores can play, asked of the cores themselves
/// (ADR 0005: `valid_extensions` is authoritative; a hardcoded table rots).
public struct CoreCatalog {
  public struct Entry: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let extensions: [String]
  }

  public let entries: [Entry]

  /// Scans `*.dylib` in the directory (sorted by filename for deterministic
  /// collision order), loading each through the trust policy to read its info.
  public init(pluginsDirectory: URL) {
    let policy = CoreTrustPolicy(allowedDirectory: pluginsDirectory)
    let listing =
      (try? FileManager.default.contentsOfDirectory(
        at: pluginsDirectory, includingPropertiesForKeys: nil)) ?? []
    let dylibs =
      listing
      .filter { $0.pathExtension == "dylib" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    entries = dylibs.compactMap { url in
      guard let library = try? CoreLibrary(url: url, policy: policy) else { return nil }
      var info = retro_system_info()
      library.symbols.getSystemInfo(&info)
      guard let namePointer = info.library_name else { return nil }
      let extensions = info.valid_extensions.map { Self.parseExtensions(String(cString: $0)) } ?? []
      return Entry(url: url, name: String(cString: namePointer), extensions: extensions)
    }
  }

  public func core(forExtension ext: String) -> Entry? {
    let lowered = ext.lowercased()
    return entries.first { $0.extensions.contains(lowered) }
  }

  public var allExtensions: [String] {
    Array(Set(entries.flatMap(\.extensions))).sorted()
  }

  static func parseExtensions(_ list: String) -> [String] {
    list.split(separator: "|").map { $0.lowercased() }
  }
}
