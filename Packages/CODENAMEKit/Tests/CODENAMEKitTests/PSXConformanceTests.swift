import CryptoKit
import Foundation
import IOSurface
import Testing

@testable import CODENAMEKit

// Local-only PlayStation verification (ADR 0007): the core, the BIOS files,
// and the disc image are all user-supplied via env vars — CI compiles this
// suite and skips it cleanly, exactly like the mGBA precedent.
//   PS1_CORE_PATH    — helper-only PSX core dylib (build/cores/helper-only/…)
//   PS1_BIOS_DIR     — directory containing the user's BIOS images (any names)
//   PS1_CONTENT_PATH — a .cue disc image
private let ps1Core = ProcessInfo.processInfo.environment["PS1_CORE_PATH"]
private let ps1BIOSDir = ProcessInfo.processInfo.environment["PS1_BIOS_DIR"]
private let ps1Content = ProcessInfo.processInfo.environment["PS1_CONTENT_PATH"]

@Suite(.serialized, .enabled(if: ps1Core != nil && ps1BIOSDir != nil && ps1Content != nil))
struct PSXConformanceTests {
  @Test func bootsDiscThroughHelperWithStagedBIOS() async throws {
    // Stage the user's BIOS images by digest into a fresh system dir —
    // the same machinery the app uses.
    let system = FileManager.default.temporaryDirectory
      .appendingPathComponent("psx-system-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
    let vault = URL(fileURLWithPath: ps1BIOSDir ?? "/nonexistent", isDirectory: true)
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: vault, includingPropertiesForKeys: nil)) ?? []
    let report = PSXBIOS.stage(files: files, into: system)
    #expect(report.missingRegions.isEmpty, "BIOS regions missing: \(report.missingRegions)")

    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let session = HelperSession(proxy: proxy)
    let maybeAV = session.open(
      corePath: ps1Core ?? "", contentPath: ps1Content,
      systemDirectory: system.path,
      saveDirectory: FileManager.default.temporaryDirectory.path)
    let av = try #require(maybeAV)
    #expect(av.baseWidth > 0)
    #expect(av.maxWidth >= av.baseWidth)
    #expect(av.framesPerSecond > 59 && av.framesPerSecond < 61)

    // 300 frames of BIOS boot — enough to reach the logo scene.
    for _ in 0..<300 {
      let done = DispatchSemaphore(value: 0)
      guard session.runFrame(onAudio: { _ in done.signal() }) else { continue }
      #expect(done.wait(timeout: .now() + 30) == .success)
    }
    let size = session.latestFrameSize
    #expect(size.width > 0)
    #expect(size.height > 0)

    // The surface must contain a real picture by now, not all-black.
    let surface = try #require(session.surface)
    IOSurfaceLock(surface, [.readOnly], nil)
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let rowBytes = IOSurfaceGetBytesPerRow(surface)
    var litPixels = 0
    for row in stride(from: 0, to: size.height, by: 8) {
      for column in stride(from: 0, to: size.width, by: 8) {
        let offset = row * rowBytes + column * 4
        if base[offset] > 16 || base[offset + 1] > 16 || base[offset + 2] > 16 {
          litPixels += 1
        }
      }
    }
    IOSurfaceUnlock(surface, [.readOnly], nil)
    #expect(litPixels > 0, "framebuffer still black after 300 frames")

    session.close()
  }
}
