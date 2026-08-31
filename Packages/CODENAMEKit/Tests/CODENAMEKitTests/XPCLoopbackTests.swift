import CryptoKit
import Foundation
import IOSurface
import Testing

@testable import CODENAMEKit

private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

// Excluded from the TSAN CI pass (libxpc internals are not our races).
@Suite struct XPCLoopbackTests {
  @Test func handshakeCrossesTheConnection() async throws {
    let host = LoopbackCoreHost()
    let version = await withCheckedContinuation { continuation in
      guard let proxy = host.proxy(errorHandler: { _ in continuation.resume(returning: -1) })
      else { return continuation.resume(returning: -2) }
      proxy.handshake(version: CoreHostWire.version) { continuation.resume(returning: $0) }
    }
    #expect(version == CoreHostWire.version)
  }

  @Test func ioSurfaceRoundTripsWithDimensions() async throws {
    let host = LoopbackCoreHost()
    let surface = try #require(
      IOSurface(properties: [
        .width: 320, .height: 224, .bytesPerElement: 4,
        .pixelFormat: UInt32(0x4247_5241),  // 'BGRA'
      ]))

    let size: (Int, Int) = await withCheckedContinuation { continuation in
      guard let proxy = host.proxy(errorHandler: { _ in continuation.resume(returning: (-1, -1)) })
      else { return continuation.resume(returning: (-2, -2)) }
      proxy.roundTripFrame(surface) { continuation.resume(returning: ($0, $1)) }
    }
    #expect(size.0 == 320)
    #expect(size.1 == 224)
  }

  @Test func wireCodesRoundTripAllFormats() {
    for format in [LibretroPixelFormat.zeroRGB1555, .rgb565, .xrgb8888] {
      #expect(LibretroPixelFormat(wireCode: format.wireCode) == format)
    }
    #expect(LibretroPixelFormat(wireCode: 9) == nil)
  }

  @Test func interfaceAllowlistsIOSurfaceForFrameArgument() {
    let classes = CoreHostWire.interface().classes(
      for: #selector(CoreHostProtocol.roundTripFrame(_:reply:)), argumentIndex: 0, ofReply: false)
    let names = classes.map { String(describing: $0) }
    #expect(names == ["IOSurface"])
  }
}

// Step C parity: the helper-hosted session must be bit-identical to the
// in-process one. Serialized: sessions are process-exclusive.
@Suite(.serialized, .enabled(if: testCorePath != nil))
struct XPCSessionParityTests {
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }

  private func inProcessRun(frames: Int) throws -> (frameHash: String, audioCount: Int) {
    let environment = EnvironmentHandler(
      systemDirectory: FileManager.default.temporaryDirectory,
      saveDirectory: FileManager.default.temporaryDirectory)
    let session = try CoreSession(
      coreURL: coreURL,
      policy: CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent()),
      environment: environment)
    defer { session.shutdown() }
    try session.loadGame(path: nil)
    session.run(frames: frames)
    let audio = session.drainAudioSamples()
    let frame = try #require(session.latestFrame)
    let digest = SHA256.hash(data: Data(frame.bytes)).map { String(format: "%02x", $0) }.joined()
    return (digest, audio.count)
  }

  @Test func helperSessionMatchesInProcessHashes() async throws {
    let frames = 60
    let expected = try inProcessRun(frames: frames)

    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)

    let opened: Bool = await withCheckedContinuation { continuation in
      proxy.openSession(
        corePath: coreURL.path, contentPath: nil,
        systemDirectory: FileManager.default.temporaryDirectory.path,
        saveDirectory: FileManager.default.temporaryDirectory.path,
        options: Data()
      ) { ok, width, height, maxWidth, maxHeight, aspect, _, _ in
        continuation.resume(
          returning: ok && width == 320 && height == 240 && maxWidth == 320 && maxHeight == 240
            && aspect > 0)
      }
    }
    #expect(opened)

    let result: (Data, Int, Data) = await withCheckedContinuation { continuation in
      proxy.runFrames(frames) { bytes, _, _, _, wireCode, audio in
        continuation.resume(returning: (bytes, wireCode, audio))
      }
    }
    let digest = SHA256.hash(data: result.0).map { String(format: "%02x", $0) }.joined()
    #expect(digest == expected.frameHash)
    #expect(LibretroPixelFormat(wireCode: result.1) == .rgb565)
    #expect(result.2.count == expected.audioCount * MemoryLayout<Int16>.size)

    await withCheckedContinuation { continuation in
      proxy.closeSession { continuation.resume() }
    }
  }

  @Test func sharedSurfaceCarriesConvertedFrames() async throws {
    let frames = 30
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let maybeSurface = CoreHostWire.makeFrameSurface(width: 320, height: 240)
    let surface = try #require(maybeSurface)

    let opened: Bool = await withCheckedContinuation { continuation in
      proxy.openSession(
        corePath: coreURL.path, contentPath: nil,
        systemDirectory: FileManager.default.temporaryDirectory.path,
        saveDirectory: FileManager.default.temporaryDirectory.path,
        options: Data()
      ) { ok, _, _, _, _, _, _, _ in continuation.resume(returning: ok) }
    }
    #expect(opened)

    let attached: Bool = await withCheckedContinuation { continuation in
      proxy.attachFrameSurface(surface) { continuation.resume(returning: $0) }
    }
    #expect(attached)

    let result: (Bool, Int, Int) = await withCheckedContinuation { continuation in
      proxy.runFramesShared(frames, buttons: 0) { ok, width, height, _ in
        continuation.resume(returning: (ok, width, height))
      }
    }
    #expect(result.0)
    #expect(result.1 == 320)
    #expect(result.2 == 240)

    // TestCore fills the framebuffer with the frame counter; after 30 frames
    // pixel 0 is RGB565 value 30 → converted BGRA (B,G,R,A).
    IOSurfaceLock(surface, [.readOnly], nil)
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let expected = PixelConverter.toBGRA8(
      bytes: [UInt8(frames & 0xFF), UInt8(frames >> 8)], width: 1, height: 1, pitch: 2,
      format: .rgb565)
    let pixel = [base[0], base[1], base[2], base[3]]
    IOSurfaceUnlock(surface, [.readOnly], nil)
    #expect(pixel == expected)

    await withCheckedContinuation { continuation in
      proxy.closeSession { continuation.resume() }
    }
  }

  @Test func undersizedSurfaceIsRefused() async throws {
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let maybeSurface = CoreHostWire.makeFrameSurface(width: 16, height: 16)
    let tiny = try #require(maybeSurface)

    let opened: Bool = await withCheckedContinuation { continuation in
      proxy.openSession(
        corePath: coreURL.path, contentPath: nil,
        systemDirectory: FileManager.default.temporaryDirectory.path,
        saveDirectory: FileManager.default.temporaryDirectory.path,
        options: Data()
      ) { ok, _, _, _, _, _, _, _ in continuation.resume(returning: ok) }
    }
    #expect(opened)
    _ = await withCheckedContinuation { continuation in
      proxy.attachFrameSurface(tiny) { continuation.resume(returning: $0) }
    }
    let ok: Bool = await withCheckedContinuation { continuation in
      proxy.runFramesShared(1, buttons: 0) { ok, _, _, _ in continuation.resume(returning: ok) }
    }
    #expect(!ok)
    await withCheckedContinuation { continuation in
      proxy.closeSession { continuation.resume() }
    }
  }

  @Test func inputMaskReachesTheCoreOverTheWire() async throws {
    // TestCore echoes the B button into pixel 1; press B via the v2 mask
    // and read it back out of the shared surface after conversion.
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let maybeSurface = CoreHostWire.makeFrameSurface(width: 320, height: 240)
    let surface = try #require(maybeSurface)

    let opened: Bool = await withCheckedContinuation { continuation in
      proxy.openSession(
        corePath: coreURL.path, contentPath: nil,
        systemDirectory: FileManager.default.temporaryDirectory.path,
        saveDirectory: FileManager.default.temporaryDirectory.path,
        options: Data()
      ) { ok, _, _, _, _, _, _, _ in continuation.resume(returning: ok) }
    }
    #expect(opened)
    _ = await withCheckedContinuation { continuation in
      proxy.attachFrameSurface(surface) { continuation.resume(returning: $0) }
    }

    let bButton = UInt32(1) << RetroPadButton.b.deviceID
    let ok: Bool = await withCheckedContinuation { continuation in
      proxy.runFramesShared(1, buttons: bButton) { ok, _, _, _ in
        continuation.resume(returning: ok)
      }
    }
    #expect(ok)

    IOSurfaceLock(surface, [.readOnly], nil)
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let pressed = PixelConverter.toBGRA8(
      bytes: [1, 0], width: 1, height: 1, pitch: 2, format: .rgb565)
    let pixel1 = [base[4], base[5], base[6], base[7]]
    IOSurfaceUnlock(surface, [.readOnly], nil)
    #expect(pixel1 == pressed)

    await withCheckedContinuation { continuation in
      proxy.closeSession { continuation.resume() }
    }
  }

  @Test func saveRAMRoundTripsOverTheWire() async throws {
    // TestCore stamps sram[0] with the frame counter; snapshot it, mutate
    // the copy, restore, and the next snapshot must return the mutation.
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)

    let opened: Bool = await withCheckedContinuation { continuation in
      proxy.openSession(
        corePath: coreURL.path, contentPath: nil,
        systemDirectory: FileManager.default.temporaryDirectory.path,
        saveDirectory: FileManager.default.temporaryDirectory.path,
        options: Data()
      ) { ok, _, _, _, _, _, _, _ in continuation.resume(returning: ok) }
    }
    #expect(opened)

    _ = await withCheckedContinuation { continuation in
      proxy.runFrames(5) { _, _, _, _, _, _ in continuation.resume(returning: true) }
    }
    let snapshot: Data = await withCheckedContinuation { continuation in
      proxy.saveRAMSnapshot { continuation.resume(returning: $0) }
    }
    #expect(!snapshot.isEmpty)
    #expect(snapshot[0] == 5)

    var mutated = snapshot
    mutated[0] = 99
    let restored: Bool = await withCheckedContinuation { continuation in
      proxy.restoreSaveRAM(mutated) { continuation.resume(returning: $0) }
    }
    #expect(restored)
    let replayed: Data = await withCheckedContinuation { continuation in
      proxy.saveRAMSnapshot { continuation.resume(returning: $0) }
    }
    #expect(replayed[0] == 99)

    await withCheckedContinuation { continuation in
      proxy.closeSession { continuation.resume() }
    }
  }

  @Test func saveRAMWithoutSessionRepliesEmpty() async {
    let host = LoopbackCoreHost()
    guard let proxy = host.proxy(errorHandler: { _ in }) else { return }
    let snapshot: Data = await withCheckedContinuation { continuation in
      proxy.saveRAMSnapshot { continuation.resume(returning: $0) }
    }
    #expect(snapshot.isEmpty)
  }

  @Test func probeValidatesRealCoresAndRejectsImposters() async throws {
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)

    let good: (Bool, String) = await withCheckedContinuation { continuation in
      proxy.probeCore(path: coreURL.path) { continuation.resume(returning: ($0, $1)) }
    }
    #expect(good.0)
    #expect(good.1 == "CODENAME Test Core")

    let bad: Bool = await withCheckedContinuation { continuation in
      proxy.probeCore(path: "/usr/lib/libz.dylib") { ok, _ in continuation.resume(returning: ok) }
    }
    #expect(!bad)
  }

  @Test func runFramesWithoutSessionRepliesEmpty() async {
    let host = LoopbackCoreHost()
    guard let proxy = host.proxy(errorHandler: { _ in }) else { return }
    let wireCode: Int = await withCheckedContinuation { continuation in
      proxy.runFrames(1) { _, _, _, _, code, _ in continuation.resume(returning: code) }
    }
    #expect(wireCode == -1)
  }
}
