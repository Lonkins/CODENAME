import CLibretro
import Foundation
import Testing

@testable import CODENAMEKit

// REAL_CORE_DIR points at Scripts/build-cores.sh output; the cores workflow sets it.
private let realCoreDir = ProcessInfo.processInfo.environment["REAL_CORE_DIR"]

@Suite(.enabled(if: realCoreDir != nil))
struct RealCoreLoadTests {
  @Test(arguments: [
    "genesis_plus_gx_libretro.dylib", "snes9x_libretro.dylib", "mgba_libretro.dylib",
  ])
  func upstreamCorePassesLoader(_ name: String) throws {
    let directory = URL(fileURLWithPath: realCoreDir ?? "/nonexistent", isDirectory: true)
    let policy = CoreTrustPolicy(allowedDirectory: directory)
    let library = try CoreLibrary(url: directory.appendingPathComponent(name), policy: policy)

    #expect(library.symbols.apiVersion() == UInt32(RETRO_API_VERSION))
    var info = retro_system_info()
    library.symbols.getSystemInfo(&info)
    let coreName = String(cString: info.library_name)
    #expect(!coreName.isEmpty)
  }
}
