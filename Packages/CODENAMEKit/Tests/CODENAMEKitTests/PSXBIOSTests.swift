import CryptoKit
import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct PSXBIOSTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("bios-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("system"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("vault"), withIntermediateDirectories: true)
  }

  /// A synthetic file whose MD5 we register nowhere — plus a helper to make
  /// files that hash to a KNOWN digest is impossible, so recognition tests
  /// drive `recognize` through the catalog boundaries instead.
  private func write(_ name: String, bytes: [UInt8]) throws -> URL {
    let url = root.appendingPathComponent("vault/\(name)")
    try Data(bytes).write(to: url)
    return url
  }

  @Test func unknownFileIsNotRecognized() throws {
    let url = try write("random.bin", bytes: [1, 2, 3, 4])
    #expect(PSXBIOS.recognize(url) == nil)
  }

  @Test func oversizedFileIsNeverHashed() throws {
    let url = root.appendingPathComponent("vault/huge.bin")
    let size = PSXBIOS.maxImageBytes + 1
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(size))
    try handle.close()
    #expect(PSXBIOS.recognize(url) == nil)
  }

  @Test func stageReportsAllRegionsMissingForEmptyInput() {
    let system = root.appendingPathComponent("system")
    let report = PSXBIOS.stage(files: [], into: system)
    #expect(report.staged.isEmpty)
    #expect(report.missingRegions == ["America", "Europe", "Japan"])
  }

  @Test func canonicalFileAlreadyOnDiskCountsAsPresent() throws {
    let system = root.appendingPathComponent("system")
    try Data([9, 9]).write(to: system.appendingPathComponent("scph5501.bin"))
    let report = PSXBIOS.stage(files: [], into: system)
    #expect(report.missingRegions == ["Europe", "Japan"])
  }

  @Test func knownDigestTableIsWellFormed() {
    #expect(PSXBIOS.known.count == 3)
    for (digest, image) in PSXBIOS.known {
      #expect(digest.count == 32)
      #expect(image.canonicalName.hasPrefix("scph"))
      #expect(image.canonicalName.hasSuffix(".bin"))
    }
    #expect(Set(PSXBIOS.known.values.map(\.canonicalName)).count == 3)
  }
}
