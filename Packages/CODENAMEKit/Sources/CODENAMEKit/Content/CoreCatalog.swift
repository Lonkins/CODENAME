import CLibretro
import Foundation

/// What the bundled cores can play, asked of the cores themselves
/// (ADR 0005: `valid_extensions` is authoritative; a hardcoded table rots).
public struct CoreCatalog {
  public struct Entry: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let extensions: [String]
    /// The core streams content from disk itself; the host passes the path
    /// only and the cartridge size cap does not apply (ADR 0007).
    public let needsFullPath: Bool
    /// Helper-only cores (ADR 0007): the app process never dlopens them —
    /// their metadata comes from a static .info sidecar, and sessions run
    /// exclusively in CoreHost.xpc.
    public let requiresHelper: Bool
    /// Which disc system this core plays, when it plays one. Declared in
    /// the sidecar rather than matched on the core's name, so routing a
    /// multi-claimed disc extension is mechanical (ADR 0007).
    public let system: DiscSniffer.System?
  }

  public let entries: [Entry]

  /// Scans `*.dylib` in the directory (sorted by filename for deterministic
  /// collision order), loading each through the trust policy to read its
  /// info. `helperOnlyDirectory` entries are described by .info sidecars
  /// instead — those dylibs never load in this process. Sidecars live in
  /// `sidecarDirectory` (Resources in the app bundle: data in PlugIns would
  /// break the code seal), defaulting to the dylib directory for dev trees.
  public init(pluginsDirectory: URL, helperOnlyDirectory: URL? = nil, sidecarDirectory: URL? = nil)
  {
    let policy = CoreTrustPolicy(allowedDirectory: pluginsDirectory)
    let listing =
      (try? FileManager.default.contentsOfDirectory(
        at: pluginsDirectory, includingPropertiesForKeys: nil)) ?? []
    let dylibs =
      listing
      .filter { $0.pathExtension == "dylib" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    entries =
      dylibs.compactMap { url in
        guard let library = try? CoreLibrary(url: url, policy: policy) else { return nil }
        var info = retro_system_info()
        library.symbols.getSystemInfo(&info)
        guard let namePointer = info.library_name else { return nil }
        let extensions =
          info.valid_extensions.map { Self.parseExtensions(String(cString: $0)) } ?? []
        return Entry(
          url: url, name: String(cString: namePointer), extensions: extensions,
          needsFullPath: info.need_fullpath, requiresHelper: false, system: nil)
      }
      + Self.helperOnlyEntries(
        dylibs: helperOnlyDirectory, sidecars: sidecarDirectory ?? helperOnlyDirectory)
  }

  static func helperOnlyEntries(dylibs: URL?, sidecars: URL?) -> [Entry] {
    guard let dylibs, let sidecars else { return [] }
    let listing =
      (try? FileManager.default.contentsOfDirectory(
        at: sidecars, includingPropertiesForKeys: nil)) ?? []
    return
      listing
      .filter { $0.pathExtension == "info" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .compactMap { infoURL in
        let dylibURL = dylibs.appendingPathComponent(
          infoURL.deletingPathExtension().lastPathComponent + ".dylib")
        guard FileManager.default.fileExists(atPath: dylibURL.path),
          let text = try? String(contentsOf: infoURL, encoding: .utf8),
          let entry = Self.parseSidecar(text, dylibURL: dylibURL)
        else { return nil }
        return entry
      }
  }

  /// `key = value` lines: name, pipe-separated extensions, need_fullpath,
  /// system.
  static func parseSidecar(_ text: String, dylibURL: URL) -> Entry? {
    var fields: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }
      fields[parts[0].trimmingCharacters(in: .whitespaces)] =
        parts[1].trimmingCharacters(in: .whitespaces)
    }
    guard let name = fields["name"], !name.isEmpty,
      let extensionList = fields["extensions"], !extensionList.isEmpty
    else { return nil }
    return Entry(
      url: dylibURL, name: name, extensions: parseExtensions(extensionList),
      needsFullPath: fields["need_fullpath"] == "true", requiresHelper: true,
      system: parseSystem(fields["system"]))
  }

  static func parseSystem(_ name: String?) -> DiscSniffer.System? {
    switch name {
    case "playstation": return .playStation
    case "segacd": return .segaCD
    default: return nil
    }
  }

  public func core(forExtension ext: String) -> Entry? {
    cores(forExtension: ext).first
  }

  /// Every core claiming the extension, catalog order — disc extensions
  /// are legitimately multi-claimed and the caller disambiguates by
  /// content (DiscSniffer, ADR 0007).
  public func cores(forExtension ext: String) -> [Entry] {
    let lowered = ext.lowercased()
    return entries.filter { $0.extensions.contains(lowered) }
  }

  public var allExtensions: [String] {
    Array(Set(entries.flatMap(\.extensions))).sorted()
  }

  static func parseExtensions(_ list: String) -> [String] {
    list.split(separator: "|").map { $0.lowercased() }
  }
}
