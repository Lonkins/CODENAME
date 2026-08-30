import Foundation
import IOSurface

/// Wire protocol for the out-of-process core helper (ADR 0006). Deliberately
/// tiny: handshake + an IOSurface round trip prove the serialization
/// machinery; core hosting arrives with the helper's own environment.
@objc public protocol CoreHostProtocol {
  func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void)
  func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void)

  /// Step C: the helper hosts a real core session (one per service instance).
  /// Reply: ok, baseWidth, baseHeight, fps, audioSampleRate.
  func openSession(
    corePath: String, contentPath: String?, systemDirectory: String, saveDirectory: String,
    reply: @escaping @Sendable (Bool, Int, Int, Double, Double) -> Void)

  /// Runs N frames; replies with the latest frame (bytes, width, height,
  /// pitch, pixel-format wire code) and the drained interleaved audio.
  func runFrames(
    _ count: Int, reply: @escaping @Sendable (Data, Int, Int, Int, Int, Data) -> Void)

  func closeSession(reply: @escaping @Sendable () -> Void)

  /// Save-state round trip across the boundary (owned bytes, per the
  /// transport contract).
  func serializeState(reply: @escaping @Sendable (Data) -> Void)
  func unserializeState(_ state: Data, reply: @escaping @Sendable (Bool) -> Void)

  /// C2 transport: the app attaches a BGRA IOSurface once; runFramesShared
  /// fills it (converted, tightly row-copied) instead of shipping bytes.
  /// Audio remains message-based until profiling demands shared memory.
  func attachFrameSurface(_ surface: IOSurface, reply: @escaping @Sendable (Bool) -> Void)
  func runFramesShared(
    _ count: Int, reply: @escaping @Sendable (Bool, Int, Int, Data) -> Void)
}

extension CoreHostWire {
  /// App-side helper: a BGRA surface sized for a core's max geometry.
  public static func makeFrameSurface(width: Int, height: Int) -> IOSurface? {
    IOSurface(properties: [
      .width: width, .height: height, .bytesPerElement: 4,
      .pixelFormat: UInt32(0x4247_5241),  // 'BGRA'
    ])
  }
}

extension LibretroPixelFormat {
  /// Stable wire encoding (matches RETRO_PIXEL_FORMAT raw values).
  public var wireCode: Int {
    switch self {
    case .zeroRGB1555: 0
    case .xrgb8888: 1
    case .rgb565: 2
    }
  }

  public init?(wireCode: Int) {
    switch wireCode {
    case 0: self = .zeroRGB1555
    case 1: self = .xrgb8888
    case 2: self = .rgb565
    default: return nil
    }
  }
}

public enum CoreHostWire {
  public static let version = 1

  public static func interface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: CoreHostProtocol.self)
    let allowed = NSSet(object: IOSurface.self) as? Set<AnyHashable> ?? []
    interface.setClasses(
      allowed,
      for: #selector(CoreHostProtocol.roundTripFrame(_:reply:)),
      argumentIndex: 0, ofReply: false)
    interface.setClasses(
      allowed,
      for: #selector(CoreHostProtocol.attachFrameSurface(_:reply:)),
      argumentIndex: 0, ofReply: false)
    return interface
  }
}

/// Helper-side implementation. @unchecked Sendable: the session and its
/// non-Sendable state are confined to one serial queue — the helper's
/// equivalent of the app's dedicated core thread.
public final class CoreHostService: NSObject, CoreHostProtocol, @unchecked Sendable {
  private let coreQueue = DispatchQueue(label: "CODENAME.CoreHost.core")
  private var session: CoreSession?

  public func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void) {
    reply(CoreHostWire.version)
  }

  public func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void) {
    reply(IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
  }

  public func openSession(
    corePath: String, contentPath: String?, systemDirectory: String, saveDirectory: String,
    reply: @escaping @Sendable (Bool, Int, Int, Double, Double) -> Void
  ) {
    coreQueue.async { [self] in
      let coreURL = URL(fileURLWithPath: corePath)
      let environment = EnvironmentHandler(
        systemDirectory: URL(fileURLWithPath: systemDirectory),
        saveDirectory: URL(fileURLWithPath: saveDirectory))
      let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())
      do {
        let session = try CoreSession(
          coreURL: coreURL, policy: policy, environment: environment)
        try session.loadGame(path: contentPath)
        self.session = session
        let av = session.avInfo
        reply(
          true, av?.baseSize.width ?? 0, av?.baseSize.height ?? 0,
          av?.framesPerSecond ?? 0, av?.audioSampleRate ?? 0)
      } catch {
        reply(false, 0, 0, 0, 0)
      }
    }
  }

  public func runFrames(
    _ count: Int, reply: @escaping @Sendable (Data, Int, Int, Int, Int, Data) -> Void
  ) {
    coreQueue.async { [self] in
      guard let session else {
        return reply(Data(), 0, 0, 0, -1, Data())
      }
      session.run(frames: count)
      let audio = session.drainAudioSamples()
      let audioData = audio.withUnsafeBufferPointer { Data(buffer: $0) }
      guard let frame = session.latestFrame else {
        return reply(Data(), 0, 0, 0, -1, audioData)
      }
      reply(
        Data(frame.bytes), frame.width, frame.height, frame.pitch,
        frame.pixelFormat.wireCode, audioData)
    }
  }

  public func closeSession(reply: @escaping @Sendable () -> Void) {
    coreQueue.async { [self] in
      session?.shutdown()
      session = nil
      frameSurface = nil
      reply()
    }
  }

  public func serializeState(reply: @escaping @Sendable (Data) -> Void) {
    coreQueue.async { [self] in
      let bytes = (try? session?.serialize()) ?? []
      reply(Data(bytes))
    }
  }

  public func unserializeState(_ state: Data, reply: @escaping @Sendable (Bool) -> Void) {
    coreQueue.async { [self] in
      guard let session else { return reply(false) }
      reply((try? session.unserialize([UInt8](state))) != nil)
    }
  }

  private var frameSurface: IOSurface?

  public func attachFrameSurface(_ surface: IOSurface, reply: @escaping @Sendable (Bool) -> Void) {
    coreQueue.async { [self] in
      frameSurface = surface
      reply(true)
    }
  }

  public func runFramesShared(
    _ count: Int, reply: @escaping @Sendable (Bool, Int, Int, Data) -> Void
  ) {
    coreQueue.async { [self] in
      guard let session, let frameSurface else {
        return reply(false, 0, 0, Data())
      }
      session.run(frames: count)
      let audio = session.drainAudioSamples()
      let audioData = audio.withUnsafeBufferPointer { Data(buffer: $0) }
      guard let frame = session.latestFrame,
        frame.width <= IOSurfaceGetWidth(frameSurface),
        frame.height <= IOSurfaceGetHeight(frameSurface)
      else {
        return reply(false, 0, 0, audioData)
      }

      let bgra = PixelConverter.toBGRA8(
        bytes: frame.bytes, width: frame.width, height: frame.height,
        pitch: frame.pitch, format: frame.pixelFormat)
      IOSurfaceLock(frameSurface, [], nil)
      let base = IOSurfaceGetBaseAddress(frameSurface)
      let surfaceRowBytes = IOSurfaceGetBytesPerRow(frameSurface)
      bgra.withUnsafeBytes { source in
        guard let sourceBase = source.baseAddress else { return }
        for row in 0..<frame.height {
          memcpy(
            base.advanced(by: row * surfaceRowBytes),
            sourceBase.advanced(by: row * frame.width * 4),
            frame.width * 4)
        }
      }
      IOSurfaceUnlock(frameSurface, [], nil)
      reply(true, frame.width, frame.height, audioData)
    }
  }
}

/// Anonymous-listener loopback: the full NSXPCConnection serialization path
/// with no launchd involvement — CI-deterministic (ADR 0006 verification
/// strategy). @unchecked Sendable: connection/listener are internally
/// thread-safe; service is stateless.
public final class LoopbackCoreHost: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener: NSXPCListener
  private let connection: NSXPCConnection
  private let service = CoreHostService()

  override public init() {
    listener = NSXPCListener.anonymous()
    connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    super.init()
    listener.delegate = self
    listener.resume()
    connection.remoteObjectInterface = CoreHostWire.interface()
    connection.resume()
  }

  deinit {
    connection.invalidate()
    listener.invalidate()
  }

  public func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = CoreHostWire.interface()
    newConnection.exportedObject = service
    newConnection.resume()
    return true
  }

  public func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> CoreHostProtocol? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? CoreHostProtocol
  }
}
