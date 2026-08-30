import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct CoreRoutingTests {
  private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("routing-\(UUID().uuidString)", isDirectory: true)

  init() throws {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("PlugIns"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
  }

  private func file(_ relative: String) throws -> URL {
    let url = root.appendingPathComponent(relative)
    try Data("x".utf8).write(to: url)
    return url
  }

  @Test func bundledCoreIsCurated() throws {
    let plugins = root.appendingPathComponent("PlugIns")
    let core = try file("PlugIns/snes9x_libretro.dylib")
    #expect(CoreRouting.origin(of: core, bundledPlugInsDirectory: plugins) == .curated)
  }

  @Test func outsideCoreIsUserSupplied() throws {
    let plugins = root.appendingPathComponent("PlugIns")
    let core = try file("Downloads/mystery_core.dylib")
    #expect(CoreRouting.origin(of: core, bundledPlugInsDirectory: plugins) == .userSupplied)
  }

  @Test func symlinkIntoPlugInsIsUserSupplied() throws {
    let plugins = root.appendingPathComponent("PlugIns")
    let outside = try file("Downloads/evil.dylib")
    let link = plugins.appendingPathComponent("evil.dylib")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    #expect(CoreRouting.origin(of: link, bundledPlugInsDirectory: plugins) == .userSupplied)
  }

  @Test func onlyUserSuppliedRequiresHelper() {
    #expect(!CoreRouting.requiresHelper(.curated))
    #expect(CoreRouting.requiresHelper(.userSupplied))
  }
}
