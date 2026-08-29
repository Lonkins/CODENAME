import CLibretro
import Foundation
import Testing

@testable import CODENAMEKit

// TEST_CORE_PATH points at the SwiftPM-built libTestCore.dylib; CI sets it.
private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

@Suite(.enabled(if: testCorePath != nil))
struct CoreLibraryTests {
  // Suite is gated on the env var; the fallback path never runs.
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }
  private var policy: CoreTrustPolicy {
    CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())
  }

  @Test func loadsAndReportsAPIVersion() throws {
    let library = try CoreLibrary(url: coreURL, policy: policy)
    #expect(library.symbols.apiVersion() == UInt32(RETRO_API_VERSION))
  }

  @Test func readsSystemInfo() throws {
    let library = try CoreLibrary(url: coreURL, policy: policy)
    var info = retro_system_info()
    library.symbols.getSystemInfo(&info)
    #expect(String(cString: info.library_name) == "CODENAME Test Core")
    #expect(String(cString: info.library_version) == "1.0")
  }

  @Test func rejectsLibraryMissingRetroSymbols() {
    let libz = URL(fileURLWithPath: "/usr/lib/libz.dylib")
    let permissive = CoreTrustPolicy(allowedDirectory: URL(fileURLWithPath: "/usr/lib"))
    #expect(throws: (any Error).self) {
      try CoreLibrary(url: libz, policy: permissive)
    }
  }

  @Test func policyRunsBeforeOpen() {
    let jail = CoreTrustPolicy(
      allowedDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("empty-jail"))
    #expect(throws: LoadError.outsideAllowedDirectory(coreURL.path)) {
      try CoreLibrary(url: coreURL, policy: jail)
    }
  }
}
