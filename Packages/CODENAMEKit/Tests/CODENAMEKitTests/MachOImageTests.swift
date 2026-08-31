import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct MachOImageTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("macho-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private func file(_ name: String, _ bytes: [UInt8]) throws -> URL {
    let url = root.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url
  }

  @Test func acceptsAThinArm64Image() throws {
    // MH_MAGIC_64 as it sits on disk, little-endian.
    let url = try file("thin.dylib", [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01])
    #expect(MachOImage.isLoadable(at: url))
  }

  @Test func acceptsAUniversalImage() throws {
    let url = try file("fat.dylib", [0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02])
    #expect(MachOImage.isLoadable(at: url))
  }

  @Test func rejectsSomethingThatIsNotAnImageAtAll() throws {
    let url = try file("notes.dylib", Array("this is not a core".utf8))
    #expect(MachOImage.isLoadable(at: url) == false)
  }

  @Test func rejectsAFileTooShortToHaveMagic() throws {
    #expect(MachOImage.isLoadable(at: try file("stub.dylib", [0xCF, 0xFA])) == false)
    #expect(MachOImage.isLoadable(at: try file("empty.dylib", [])) == false)
  }

  @Test func rejectsADirectory() throws {
    let url = root.appendingPathComponent("bundle.dylib", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    #expect(MachOImage.isLoadable(at: url) == false)
  }

  @Test func rejectsAnImplausiblyLargeFile() throws {
    // Sparse: the size is the point, not the bytes. A core the helper is
    // asked to dlopen has a plausible upper bound, and refusing early keeps
    // absurd input away from the dynamic linker.
    let url = try file("huge.dylib", [0xCF, 0xFA, 0xED, 0xFE])
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(MachOImage.maxImageBytes + 1))
    try handle.close()
    #expect(MachOImage.isLoadable(at: url) == false)
  }
}
