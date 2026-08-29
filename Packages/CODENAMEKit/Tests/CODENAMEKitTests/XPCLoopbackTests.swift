import Foundation
import IOSurface
import Testing

@testable import CODENAMEKit

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

  @Test func interfaceAllowlistsIOSurfaceForFrameArgument() {
    let classes = CoreHostWire.interface().classes(
      for: #selector(CoreHostProtocol.roundTripFrame(_:reply:)), argumentIndex: 0, ofReply: false)
    #expect(classes.contains { $0 == IOSurface.self })
    #expect(classes.count == 1)
  }
}
