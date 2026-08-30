import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct DiscSnifferTests {
  private let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("sniff-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private func writeDisc(_ name: String, magic: String, at offset: Int = 0x9340) throws -> URL {
    var bytes = [UInt8](repeating: 0, count: offset + magic.count + 16)
    bytes.replaceSubrange(offset..<(offset + magic.count), with: Array(magic.utf8))
    let bin = root.appendingPathComponent("\(name).bin")
    try Data(bytes).write(to: bin)
    let cue = root.appendingPathComponent("\(name).cue")
    try Data("FILE \"\(name).bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8).write(to: cue)
    return cue
  }

  @Test func identifiesPlayStationDiscThroughItsCue() throws {
    let cue = try writeDisc("psx", magic: "Sony Computer Entertainment Amer")
    #expect(DiscSniffer.identify(contentURL: cue) == .playStation)
  }

  @Test func identifiesSegaCDDisc() throws {
    let cue = try writeDisc("scd", magic: "SEGADISCSYSTEM", at: 0x10)
    #expect(DiscSniffer.identify(contentURL: cue) == .segaCD)
  }

  @Test func unknownWhenNoMagicInWindow() throws {
    let cue = try writeDisc("mystery", magic: "NOTHING RECOGNIZABLE")
    #expect(DiscSniffer.identify(contentURL: cue) == .unknown)
  }

  @Test func unknownForDanglingCue() throws {
    let cue = root.appendingPathComponent("ghost.cue")
    try Data("FILE \"missing.bin\" BINARY\n".utf8).write(to: cue)
    #expect(DiscSniffer.identify(contentURL: cue) == .unknown)
  }
}
