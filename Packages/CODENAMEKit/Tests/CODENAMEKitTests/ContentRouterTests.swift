import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct ContentRouterTests {
  private let root: URL
  private var plugIns: URL { root.appendingPathComponent("PlugIns", isDirectory: true) }
  private var helperOnly: URL { plugIns.appendingPathComponent("HelperOnly", isDirectory: true) }

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: helperOnly, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("elsewhere", isDirectory: true),
      withIntermediateDirectories: true)
  }

  private func stub(_ relative: String) throws -> URL {
    let url = root.appendingPathComponent(relative)
    try Data("stub".utf8).write(to: url)
    return url
  }

  private func entry(
    _ url: URL, name: String, extensions: [String], helper: Bool,
    needsFullPath: Bool = false, system: DiscSniffer.System? = nil
  ) -> CoreCatalog.Entry {
    CoreCatalog.Entry(
      url: url, name: name, extensions: extensions, needsFullPath: needsFullPath,
      requiresHelper: helper, system: system)
  }

  // MARK: - Host derivation (ADR 0001/0007)

  @Test func bundledCoreRunsInProcess() throws {
    let core = try stub("PlugIns/snes9x_libretro.dylib")
    #expect(ContentRouter.host(forCore: core, plugInsDirectory: plugIns) == .inProcess)
  }

  @Test func helperOnlyCoreRunsInTheHelperEvenThoughItShipsInTheBundle() throws {
    // The GPL boundary (ADR 0007): placement under HelperOnly/ decides the
    // host, and no caller gets to say otherwise.
    let core = try stub("PlugIns/HelperOnly/mednafen_psx_libretro.dylib")
    #expect(ContentRouter.host(forCore: core, plugInsDirectory: plugIns) == .helper)
  }

  @Test func userSuppliedCoreRunsInTheHelper() throws {
    let core = try stub("elsewhere/whatever_libretro.dylib")
    #expect(ContentRouter.host(forCore: core, plugInsDirectory: plugIns) == .helper)
  }

  @Test func inProcessHostingMeansExactlyWhatTheTrustPolicyAllows() throws {
    // One predicate, so "routed in process" and "may be dlopened here"
    // cannot drift apart the way they did before.
    let policy = CoreTrustPolicy(allowedDirectory: plugIns)
    for relative in [
      "PlugIns/snes9x_libretro.dylib", "PlugIns/HelperOnly/gpl_libretro.dylib",
      "elsewhere/user_libretro.dylib",
    ] {
      let core = try stub(relative)
      let allowed = (try? policy.validate(core)) != nil
      #expect(
        (ContentRouter.host(forCore: core, plugInsDirectory: plugIns) == .inProcess)
          == allowed)
    }
  }

  // MARK: - Content routing

  @Test func routesContentToTheCoreClaimingItsExtension() throws {
    let snes = try stub("PlugIns/snes9x_libretro.dylib")
    let route = try ContentRouter.route(
      contentURL: URL(fileURLWithPath: "/games/Mario.sfc"),
      in: [entry(snes, name: "Snes9x", extensions: ["sfc", "smc"], helper: false)],
      plugInsDirectory: plugIns, sizeInBytes: 512 * 1024)
    #expect(route.coreURL == snes)
    #expect(route.host == .inProcess)
    #expect(route.prerequisite == nil)
  }

  @Test func libraryRouteCannotDropHelperHosting() throws {
    // The defect this type exists to make impossible: the library play path
    // resolved a core by its stored id and started it in process.
    let psx = try stub("PlugIns/HelperOnly/mednafen_psx_libretro.dylib")
    let entries = [
      entry(
        psx, name: "Beetle PSX", extensions: ["cue", "chd"], helper: true,
        needsFullPath: true, system: .playStation)
    ]
    let route = try ContentRouter.route(
      contentURL: URL(fileURLWithPath: "/games/Crash.cue"),
      preferredCoreID: "mednafen_psx_libretro",
      in: entries, plugInsDirectory: plugIns, sizeInBytes: 700 * 1024 * 1024)
    #expect(route.coreURL == psx)
    #expect(route.host == .helper)
    #expect(route.prerequisite == .playStationBIOS)
  }

  @Test func unknownCoreIDFallsBackToExtensionRouting() throws {
    let snes = try stub("PlugIns/snes9x_libretro.dylib")
    let route = try ContentRouter.route(
      contentURL: URL(fileURLWithPath: "/games/Mario.sfc"), preferredCoreID: "gone_libretro",
      in: [entry(snes, name: "Snes9x", extensions: ["sfc"], helper: false)],
      plugInsDirectory: plugIns, sizeInBytes: nil)
    #expect(route.coreURL == snes)
  }

  @Test func discContentDisambiguatesBetweenCoresClaimingTheExtension() throws {
    // .cue is claimed by the Sega CD core as well; the disc decides.
    let disc = try writePlayStationDisc()
    let genesis = try stub("PlugIns/genesis_plus_gx_libretro.dylib")
    let psx = try stub("PlugIns/HelperOnly/mednafen_psx_libretro.dylib")
    let entries = [
      entry(genesis, name: "Genesis Plus GX", extensions: ["md", "cue"], helper: false),
      entry(
        psx, name: "Beetle PSX", extensions: ["cue"], helper: true,
        needsFullPath: true, system: .playStation),
    ]
    let route = try ContentRouter.route(
      contentURL: disc, in: entries, plugInsDirectory: plugIns, sizeInBytes: nil)
    #expect(route.coreURL == psx)
    #expect(route.host == .helper)
  }

  @Test func rejectsContentNoCoreClaims() throws {
    let snes = try stub("PlugIns/snes9x_libretro.dylib")
    #expect(throws: ContentRouter.Failure.unsupported(fileExtension: "docx")) {
      try ContentRouter.route(
        contentURL: URL(fileURLWithPath: "/games/Notes.docx"),
        in: [entry(snes, name: "Snes9x", extensions: ["sfc"], helper: false)],
        plugInsDirectory: plugIns, sizeInBytes: nil)
    }
  }

  @Test func rejectsOversizedCartridgeContent() throws {
    let snes = try stub("PlugIns/snes9x_libretro.dylib")
    let size = ContentRouter.maxCartridgeBytes + 1
    #expect(throws: ContentRouter.Failure.tooLarge(bytes: size)) {
      try ContentRouter.route(
        contentURL: URL(fileURLWithPath: "/games/Huge.sfc"),
        in: [entry(snes, name: "Snes9x", extensions: ["sfc"], helper: false)],
        plugInsDirectory: plugIns, sizeInBytes: size)
    }
  }

  @Test func discSizedContentIsFineForCoresThatStreamItThemselves() throws {
    let psx = try stub("PlugIns/HelperOnly/mednafen_psx_libretro.dylib")
    let route = try ContentRouter.route(
      contentURL: URL(fileURLWithPath: "/games/Crash.cue"),
      in: [
        entry(
          psx, name: "Beetle PSX", extensions: ["cue"], helper: true,
          needsFullPath: true, system: .playStation)
      ],
      plugInsDirectory: plugIns, sizeInBytes: 700 * 1024 * 1024)
    #expect(route.coreURL == psx)
  }

  // MARK: - Core-first routing (a user-supplied core picks its own content)

  @Test func routingByCoreAloneStillDerivesTheHost() throws {
    let user = try stub("elsewhere/user_libretro.dylib")
    let route = ContentRouter.route(forCore: user, plugInsDirectory: plugIns)
    #expect(route.coreURL == user)
    #expect(route.host == .helper)
  }

  private func writePlayStationDisc() throws -> URL {
    let magic = "Sony Computer Entertainment Amer"
    var bytes = [UInt8](repeating: 0, count: 0x9340 + magic.count + 16)
    bytes.replaceSubrange(0x9340..<(0x9340 + magic.count), with: Array(magic.utf8))
    try Data(bytes).write(to: root.appendingPathComponent("Crash.bin"))
    let cue = root.appendingPathComponent("Crash.cue")
    try Data("FILE \"Crash.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8).write(to: cue)
    return cue
  }
}
