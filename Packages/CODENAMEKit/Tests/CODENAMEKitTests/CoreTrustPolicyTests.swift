import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct CoreTrustPolicyTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("trust-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("cores"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("elsewhere"), withIntermediateDirectories: true)
  }

  private func file(_ relative: String) throws -> URL {
    let url = root.appendingPathComponent(relative)
    try Data("stub".utf8).write(to: url)
    return url
  }

  @Test func allowsFileInsideDirectory() throws {
    let policy = CoreTrustPolicy(allowedDirectory: root.appendingPathComponent("cores"))
    try policy.validate(try file("cores/good.dylib"))
  }

  @Test func rejectsFileInSubdirectory() throws {
    // Helper-only cores (GPL, ADR 0007) live in a subdirectory precisely so
    // the app-process policy refuses them: containment means the file sits
    // DIRECTLY in the allowed directory, not anywhere beneath it.
    let policy = CoreTrustPolicy(allowedDirectory: root.appendingPathComponent("cores"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("cores/helper-only"), withIntermediateDirectories: true)
    let nested = try file("cores/helper-only/gpl.dylib")
    #expect(throws: LoadError.outsideAllowedDirectory(nested.path)) {
      try policy.validate(nested)
    }
  }

  @Test func rejectsFileOutsideDirectory() throws {
    let policy = CoreTrustPolicy(allowedDirectory: root.appendingPathComponent("cores"))
    let outside = try file("elsewhere/evil.dylib")
    #expect(throws: LoadError.outsideAllowedDirectory(outside.path)) {
      try policy.validate(outside)
    }
  }

  @Test func rejectsTraversalEscape() throws {
    let policy = CoreTrustPolicy(allowedDirectory: root.appendingPathComponent("cores"))
    _ = try file("elsewhere/evil.dylib")
    let sneaky = root.appendingPathComponent("cores/../elsewhere/evil.dylib")
    #expect(throws: (any Error).self) { try policy.validate(sneaky) }
  }

  @Test func rejectsSymlinkEscape() throws {
    let policy = CoreTrustPolicy(allowedDirectory: root.appendingPathComponent("cores"))
    let target = try file("elsewhere/evil.dylib")
    let link = root.appendingPathComponent("cores/link.dylib")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: (any Error).self) { try policy.validate(link) }
  }

  @Test func rejectsUnsignedWhenTeamRequired() throws {
    let policy = CoreTrustPolicy(
      allowedDirectory: root.appendingPathComponent("cores"), requiredTeamID: "TEAMID1234")
    let unsigned = try file("cores/unsigned.dylib")
    #expect(throws: (any Error).self) { try policy.validate(unsigned) }
  }
}
