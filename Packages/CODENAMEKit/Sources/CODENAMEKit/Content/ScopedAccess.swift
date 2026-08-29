import Foundation

/// Pairs start/stopAccessingSecurityScopedResource with object lifetime so
/// the pairing cannot drift (ADR 0001: bookmark lifecycle is one module).
/// Hold one for as long as the resource is in use — a play session keeps its
/// ScopedAccess alive from before loadGame until after shutdown.
public final class ScopedAccess: Sendable {
  public let url: URL
  private let didStart: Bool

  public init(url: URL) {
    self.url = url
    didStart = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStart {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

public enum Bookmark {
  /// App-scoped, read-only security bookmark by default; `securityScoped:
  /// false` exercises the same path in unsandboxed test processes.
  public static func create(for url: URL, securityScoped: Bool = true) throws -> Data {
    try url.bookmarkData(
      options: securityScoped ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : [],
      includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  public static func resolve(
    _ data: Data, securityScoped: Bool = true
  ) throws -> (url: URL, isStale: Bool) {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: securityScoped ? [.withSecurityScope] : [],
      relativeTo: nil, bookmarkDataIsStale: &isStale)
    return (url, isStale)
  }
}
