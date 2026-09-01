import CLibretro
import Foundation
import IOSurface

/// Wire protocol for the out-of-process core helper (ADR 0006). Deliberately
/// tiny: handshake + an IOSurface round trip prove the serialization
/// machinery; core hosting arrives with the helper's own environment.
@objc public protocol CoreHostProtocol {
  func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void)
  func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void)

  /// Step C: the helper hosts a real core session (one per service instance).
  /// Reply: ok, base width/height, max width/height, aspect ratio, fps,
  /// audio rate. The shared IOSurface must be sized from MAX geometry —
  /// cores switch video modes mid-session (v2).
  /// v3: `options` is a JSON `[String: String]` of stored option selections,
  /// seeded before the core declares anything — cores declare during
  /// retro_set_environment, which runs inside the session initializer.
  /// v4: `contentBytes` carries cartridge content the app already read, so
  /// the helper needs no access to the user's files; `contentPath` remains
  /// the label cores peek at, and is the real path for `need_fullpath`
  /// cores, which open it themselves.
  /// v5: `disc` is a JSON `DiscStaging.Payload` and `contentHandles` are the
  /// descriptors it names, in order — disc images are too large to send and
  /// `need_fullpath` cores open sibling tracks themselves, so the helper
  /// rebuilds the content in its own container from what the app opened.
  /// v6: `system` is a JSON `DiscStaging.Payload` naming the BIOS images
  /// `systemHandles` carries, staged the same way — cores reach them
  /// through GET_SYSTEM_DIRECTORY, which otherwise points into the app's
  /// container. `systemDirectory` remains the fallback while the helper can
  /// still read it.
  func openSession(
    corePath: String, contentPath: String?, contentBytes: Data,
    disc: Data, contentHandles: [FileHandle],
    system: Data, systemHandles: [FileHandle],
    systemDirectory: String, saveDirectory: String, options: Data,
    reply: @escaping @Sendable (Bool, Int, Int, Int, Int, Double, Double, Double) -> Void)

  /// v3: what the hosted core declared and what the helper resolved, as a
  /// JSON `CoreOptionsSnapshot`. Empty when there is no session.
  func optionsSnapshot(reply: @escaping @Sendable (Data) -> Void)

  /// Runs N frames; replies with the latest frame (bytes, width, height,
  /// pitch, pixel-format wire code) and the drained interleaved audio.
  func runFrames(
    _ count: Int, reply: @escaping @Sendable (Data, Int, Int, Int, Int, Data) -> Void)

  func closeSession(reply: @escaping @Sendable () -> Void)

  /// Step D: validate an arbitrary core WITHOUT a session — the untrusted
  /// dylib is dlopen'd only inside the helper process. Reply: ok, coreName.
  func probeCore(path: String, reply: @escaping @Sendable (Bool, String) -> Void)

  /// Save-state round trip across the boundary (owned bytes, per the
  /// transport contract).
  func serializeState(reply: @escaping @Sendable (Data) -> Void)
  func unserializeState(_ state: Data, reply: @escaping @Sendable (Bool) -> Void)

  /// C2 transport: the app attaches a BGRA IOSurface once; runFramesShared
  /// fills it (converted, tightly row-copied) instead of shipping bytes.
  /// Audio remains message-based until profiling demands shared memory.
  func attachFrameSurface(_ surface: IOSurface, reply: @escaping @Sendable (Bool) -> Void)
  /// v2: `buttons` is the port-0 RetroPad state as a raw bit mask (bit N =
  /// RETRO_DEVICE_ID_JOYPAD_N), latched for every frame in the batch.
  func runFramesShared(
    _ count: Int, buttons: UInt32, reply: @escaping @Sendable (Bool, Int, Int, Data) -> Void)

  /// v2: save-RAM (battery/memcard) persistence across the boundary — owned
  /// bytes both ways, per the transport contract.
  func saveRAMSnapshot(reply: @escaping @Sendable (Data) -> Void)
  func restoreSaveRAM(_ data: Data, reply: @escaping @Sendable (Bool) -> Void)
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
  public static let version = 6

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
    // The descriptors for disc tracks travel as an array of file handles.
    let handleClasses =
      NSSet(array: [NSArray.self, FileHandle.self]) as? Set<AnyHashable> ?? []
    let openSelector = #selector(
      CoreHostProtocol.openSession(
        corePath:contentPath:contentBytes:disc:contentHandles:system:systemHandles:systemDirectory:
        saveDirectory:options:reply:))
    interface.setClasses(handleClasses, for: openSelector, argumentIndex: 4, ofReply: false)
    interface.setClasses(handleClasses, for: openSelector, argumentIndex: 6, ofReply: false)
    return interface
  }
}

/// Helper-side implementation. @unchecked Sendable: the session and its
/// non-Sendable state are confined to one serial queue — the helper's
/// equivalent of the app's dedicated core thread.
public final class CoreHostService: NSObject, CoreHostProtocol, @unchecked Sendable {
  private let coreQueue = DispatchQueue(label: "CODENAME.CoreHost.core")
  private var session: CoreSession?
  /// Held open for the session's lifetime — the staged content is symlinks
  /// to these descriptors, and closing them mid-session breaks the disc.
  private var contentHandles: [FileHandle] = []
  /// Held so option state can be reported back; same queue confinement.
  private var environment: EnvironmentHandler?

  /// Inside the helper's own temporary directory, which is inside its
  /// container once the service is sandboxed.
  static func stagingDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("CODENAME-content", isDirectory: true)
  }

  public func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void) {
    reply(CoreHostWire.version)
  }

  public func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void) {
    reply(IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
  }

  public func openSession(
    corePath: String, contentPath: String?, contentBytes: Data,
    disc: Data, contentHandles: [FileHandle],
    system: Data, systemHandles: [FileHandle],
    systemDirectory: String, saveDirectory: String, options: Data,
    reply: @escaping @Sendable (Bool, Int, Int, Int, Int, Double, Double, Double) -> Void
  ) {
    coreQueue.async { [self] in
      let coreURL = URL(fileURLWithPath: corePath)
      // Descriptors must outlive the session: the staged symlinks point at
      // them, and the core opens tracks lazily.
      self.contentHandles = contentHandles + systemHandles
      var resolvedSystemDirectory = systemDirectory
      if !systemHandles.isEmpty,
        let payload = try? JSONDecoder().decode(DiscStaging.Payload.self, from: system),
        let staged = try? DiscStaging.materialize(
          payload, descriptors: systemHandles.map(\.fileDescriptor),
          in: Self.stagingDirectory().appendingPathComponent("System", isDirectory: true))
      {
        resolvedSystemDirectory = staged.path
      }
      var loadPath = contentPath
      if !disc.isEmpty {
        guard let payload = try? JSONDecoder().decode(DiscStaging.Payload.self, from: disc),
          let staged = try? DiscStaging.materialize(
            payload, descriptors: contentHandles.map(\.fileDescriptor),
            in: Self.stagingDirectory())
        else {
          return reply(false, 0, 0, 0, 0, 0, 0, 0)
        }
        loadPath = staged.path
      }
      let environment = EnvironmentHandler(
        systemDirectory: URL(fileURLWithPath: resolvedSystemDirectory),
        saveDirectory: URL(fileURLWithPath: saveDirectory),
        jitCapable: true)
      // Seeded before the session exists, for the same reason as in-process.
      let stored = (try? JSONDecoder().decode([String: String].self, from: options)) ?? [:]
      environment.options.prefer(stored)
      self.environment = environment
      let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())
      do {
        let session = try CoreSession(
          coreURL: coreURL, policy: policy, environment: environment)
        try session.loadGame(path: loadPath, bytes: contentBytes.isEmpty ? nil : contentBytes)
        self.session = session
        let av = session.avInfo
        reply(
          true, av?.baseSize.width ?? 0, av?.baseSize.height ?? 0,
          av?.maxSize.width ?? 0, av?.maxSize.height ?? 0,
          av?.aspectRatio ?? 0, av?.framesPerSecond ?? 0, av?.audioSampleRate ?? 0)
      } catch {
        reply(false, 0, 0, 0, 0, 0, 0, 0)
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

  public func optionsSnapshot(reply: @escaping @Sendable (Data) -> Void) {
    coreQueue.async { [self] in
      guard let environment, session != nil else { return reply(Data()) }
      let snapshot = CoreOptionsSnapshot(
        options: environment.options.definitions,
        selected: environment.options.selectedValues)
      reply((try? JSONEncoder().encode(snapshot)) ?? Data())
    }
  }

  public func closeSession(reply: @escaping @Sendable () -> Void) {
    coreQueue.async { [self] in
      session?.shutdown()
      session = nil
      frameSurface = nil
      contentHandles = []
      reply()
    }
  }

  public func probeCore(path: String, reply: @escaping @Sendable (Bool, String) -> Void) {
    coreQueue.async {
      let url = URL(fileURLWithPath: path)
      let policy = CoreTrustPolicy(allowedDirectory: url.deletingLastPathComponent())
      guard let library = try? CoreLibrary(url: url, policy: policy) else {
        return reply(false, "")
      }
      var info = retro_system_info()
      library.symbols.getSystemInfo(&info)
      let name = info.library_name.map { String(cString: $0) } ?? ""
      reply(!name.isEmpty, name)
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

  public func saveRAMSnapshot(reply: @escaping @Sendable (Data) -> Void) {
    coreQueue.async { [self] in
      reply(Data(session?.saveRAMSnapshot() ?? []))
    }
  }

  public func restoreSaveRAM(_ data: Data, reply: @escaping @Sendable (Bool) -> Void) {
    coreQueue.async { [self] in
      guard let session else { return reply(false) }
      reply(session.restoreSaveRAM([UInt8](data)))
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
    _ count: Int, buttons: UInt32, reply: @escaping @Sendable (Bool, Int, Int, Data) -> Void
  ) {
    coreQueue.async { [self] in
      guard let session, let frameSurface else {
        return reply(false, 0, 0, Data())
      }
      session.inputState.replaceAll(with: buttons)
      session.run(frames: count)
      let audio = session.drainAudioSamples()
      let audioData = audio.withUnsafeBufferPointer { Data(buffer: $0) }
      guard let frame = session.latestFrame,
        frame.width <= IOSurfaceGetWidth(frameSurface),
        frame.height <= IOSurfaceGetHeight(frameSurface)
      else {
        return reply(false, 0, 0, audioData)
      }

      guard
        let bgra = PixelConverter.toBGRA8(
          bytes: frame.bytes, width: frame.width, height: frame.height,
          pitch: frame.pitch, format: frame.pixelFormat)
      else {
        return reply(false, 0, 0, audioData)
      }
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

  /// The client-side connection, so callers wire session lifecycle to it
  /// exactly as the app does.
  public var clientConnection: NSXPCConnection { connection }

  /// Simulates the helper going away.
  public func invalidate() {
    connection.invalidate()
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
    newConnection.invalidationHandler = { [service] in
      // The peer is gone and the helper hosts one session at a time: a
      // session it opened could otherwise never be closed, keeping a core
      // and its content loaded for the life of the process.
      service.closeSession {}
    }
    newConnection.resume()
    return true
  }

  public func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> CoreHostProtocol? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? CoreHostProtocol
  }
}
