/// A strict `major.minor.patch` version. No prerelease/build metadata until needed.
public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init?(_ string: some StringProtocol) {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    // Int("+1") parses; digits-only keeps "1.2.3" strict.
    guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
      let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
    else { return nil }
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }

  public var description: String { "\(major).\(minor).\(patch)" }
}
