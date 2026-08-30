import Foundation

/// ADR 0001's trust asymmetry as code: curated (bundled) cores may run
/// in-process; anything else is unauthenticated and runs only in the helper.
public enum CoreOrigin: Equatable, Sendable {
  case curated
  case userSupplied
}

public enum CoreRouting {
  public static func origin(of coreURL: URL, bundledPlugInsDirectory: URL) -> CoreOrigin {
    // Symlink-resolved containment, same discipline as CoreTrustPolicy: a
    // symlink pointing out of PlugIns is not a bundled core.
    let canonical = coreURL.resolvingSymlinksInPath().standardizedFileURL
    let plugins = bundledPlugInsDirectory.resolvingSymlinksInPath().standardizedFileURL
    let inside = canonical.pathComponents.starts(with: plugins.pathComponents)
    return inside ? .curated : .userSupplied
  }

  public static func requiresHelper(_ origin: CoreOrigin) -> Bool {
    origin == .userSupplied
  }
}
