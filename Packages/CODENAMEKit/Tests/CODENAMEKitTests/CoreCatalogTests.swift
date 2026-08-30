import Foundation
import Testing

@testable import CODENAMEKit

private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

@Suite(.enabled(if: testCorePath != nil))
struct CoreCatalogTests {
  private var pluginsDirectory: URL {
    URL(fileURLWithPath: testCorePath ?? "/nonexistent").deletingLastPathComponent()
  }

  @Test func discoversCoresAndTheirExtensions() {
    let catalog = CoreCatalog(pluginsDirectory: pluginsDirectory)
    let entry = catalog.entries.first { $0.name == "CODENAME Test Core" }
    #expect(entry != nil)
    #expect(entry?.extensions.contains("bin") == true)
  }

  @Test func exposesNeedFullPathFromTheCore() {
    let catalog = CoreCatalog(pluginsDirectory: pluginsDirectory)
    let entry = catalog.entries.first { $0.name == "CODENAME Test Core" }
    // TestCore reads the data buffer; a false here also pins the default
    // slurping load path for cartridge cores.
    #expect(entry?.needsFullPath == false)
  }

  @Test func routesExtensionCaseInsensitively() {
    let catalog = CoreCatalog(pluginsDirectory: pluginsDirectory)
    #expect(catalog.core(forExtension: "BIN")?.name == "CODENAME Test Core")
    #expect(catalog.core(forExtension: "bin")?.name == "CODENAME Test Core")
  }

  @Test func unknownExtensionRoutesNowhere() {
    let catalog = CoreCatalog(pluginsDirectory: pluginsDirectory)
    #expect(catalog.core(forExtension: "docx") == nil)
  }

  @Test func emptyDirectoryYieldsEmptyCatalog() {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-cores-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let catalog = CoreCatalog(pluginsDirectory: empty)
    #expect(catalog.entries.isEmpty)
  }
}

@Suite struct ExtensionListTests {
  @Test func parsesPipeSeparatedExtensions() {
    #expect(CoreCatalog.parseExtensions("md|gen|bin|smd") == ["md", "gen", "bin", "smd"])
    #expect(CoreCatalog.parseExtensions("sfc|smc") == ["sfc", "smc"])
    #expect(CoreCatalog.parseExtensions("") == [])
    #expect(CoreCatalog.parseExtensions("BIN") == ["bin"])
  }
}
