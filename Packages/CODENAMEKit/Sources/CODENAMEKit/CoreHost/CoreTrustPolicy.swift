import Foundation
import Security

/// Gate run before any `dlopen` (ADR 0001). Kernel library validation is the
/// load-time control in signed builds; this is containment + defence in depth.
public struct CoreTrustPolicy: Sendable {
  public let allowedDirectory: URL
  public let requiredTeamID: String?

  public init(allowedDirectory: URL, requiredTeamID: String? = nil) {
    self.allowedDirectory = allowedDirectory
    self.requiredTeamID = requiredTeamID
  }

  public func validate(_ url: URL) throws(LoadError) {
    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
    let allowed = allowedDirectory.resolvingSymlinksInPath().standardizedFileURL
    // Direct containment only: subdirectories are refused, so placement
    // decides what may load here (ADR 0007) — a mechanical guarantee
    // rather than a convention. Helper-hosted cores live in the helper's
    // own bundle, outside this directory entirely.
    let inside = canonical.deletingLastPathComponent().pathComponents == allowed.pathComponents
    guard inside else { throw .outsideAllowedDirectory(url.path) }

    if let requiredTeamID {
      guard teamIdentifier(of: canonical) == requiredTeamID else {
        throw .untrustedSignature(url.path)
      }
    }
  }

  private func teamIdentifier(of url: URL) -> String? {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    var info: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
      let info = info as? [String: Any]
    else { return nil }
    return info[kSecCodeInfoTeamIdentifier as String] as? String
  }
}
