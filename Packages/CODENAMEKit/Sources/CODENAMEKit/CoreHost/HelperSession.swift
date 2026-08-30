import Foundation
import IOSurface
import Synchronization

/// App-side client for a helper-hosted core session (ADR 0006/0007): owns
/// the proxy calls, the shared frame surface, and the input mirror the
/// display loop's controller writes into.
///
/// Threading: `open`/`serialize`/`saveRAM*`/`close` block their caller with
/// a timeout (loop-thread setup/teardown paths). `runFrame` never blocks —
/// one batch in flight at a time, so a slow reply degrades to frame repeat,
/// never to a blocked display-link callback.
public final class HelperSession: @unchecked Sendable {
  public struct AVInfo: Sendable {
    public let baseWidth: Int
    public let baseHeight: Int
    public let maxWidth: Int
    public let maxHeight: Int
    public let aspectRatio: Double
    public let framesPerSecond: Double
    public let audioSampleRate: Double
  }

  private static let replyTimeout: TimeInterval = 10

  public let inputState = InputState()
  public private(set) var surface: IOSurface?
  public private(set) var avInfo: AVInfo?

  private let proxy: CoreHostProtocol
  private let inFlight = Atomic<Bool>(false)
  private let packedFrameSize = Atomic<UInt64>(0)

  public init(proxy: CoreHostProtocol) {
    self.proxy = proxy
  }

  /// Opens the session and sizes the shared surface from MAX geometry
  /// (cores switch video modes mid-session). Nil on failure or timeout.
  public func open(
    corePath: String, contentPath: String?, systemDirectory: String, saveDirectory: String
  ) -> AVInfo? {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: AVInfo?
    proxy.openSession(
      corePath: corePath, contentPath: contentPath,
      systemDirectory: systemDirectory, saveDirectory: saveDirectory
    ) { ok, baseW, baseH, maxW, maxH, aspect, fps, rate in
      if ok {
        result = AVInfo(
          baseWidth: baseW, baseHeight: baseH, maxWidth: maxW, maxHeight: maxH,
          aspectRatio: aspect, framesPerSecond: fps, audioSampleRate: rate)
      }
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + Self.replyTimeout) == .success else { return nil }
    guard let opened = result else { return nil }

    guard
      let surface = CoreHostWire.makeFrameSurface(width: opened.maxWidth, height: opened.maxHeight)
    else { return nil }
    nonisolated(unsafe) var attached = false
    let attachSemaphore = DispatchSemaphore(value: 0)
    proxy.attachFrameSurface(surface) { ok in
      attached = ok
      attachSemaphore.signal()
    }
    guard attachSemaphore.wait(timeout: .now() + Self.replyTimeout) == .success, attached
    else { return nil }

    self.surface = surface
    self.avInfo = opened
    packedFrameSize.store(Self.pack(opened.baseWidth, opened.baseHeight), ordering: .relaxed)
    return opened
  }

  /// Sends one frame batch with the current input mask. Returns false when a
  /// batch is already in flight — the caller re-presents the last frame.
  /// `onAudio` runs on the connection's reply queue with the drained samples.
  public func runFrame(onAudio: @escaping @Sendable (Data) -> Void) -> Bool {
    guard !inFlight.exchange(true, ordering: .acquiring) else { return false }
    proxy.runFramesShared(1, buttons: inputState.raw) { [self] ok, width, height, audio in
      if ok {
        packedFrameSize.store(Self.pack(width, height), ordering: .relaxed)
      }
      // Release BEFORE the callback: a caller that chains its next frame
      // from onAudio must never race the in-flight guard.
      inFlight.store(false, ordering: .releasing)
      if ok {
        onAudio(audio)
      }
    }
    return true
  }

  /// Geometry of the newest frame the helper wrote into the surface.
  public var latestFrameSize: (width: Int, height: Int) {
    Self.unpack(packedFrameSize.load(ordering: .relaxed))
  }

  public func serializeState() -> Data? {
    var reply: Data?
    waitReply(timeoutNil: &reply) { done in
      self.proxy.serializeState { data in done(data.isEmpty ? nil : data) }
    }
    return reply
  }

  public func unserializeState(_ state: Data) -> Bool {
    var reply: Bool?
    waitReply(timeoutNil: &reply) { done in
      self.proxy.unserializeState(state) { done($0) }
    }
    return reply ?? false
  }

  public func saveRAMSnapshot() -> Data? {
    var reply: Data?
    waitReply(timeoutNil: &reply) { done in
      self.proxy.saveRAMSnapshot { data in done(data.isEmpty ? nil : data) }
    }
    return reply
  }

  public func restoreSaveRAM(_ bytes: Data) -> Bool {
    var reply: Bool?
    waitReply(timeoutNil: &reply) { done in
      self.proxy.restoreSaveRAM(bytes) { done($0) }
    }
    return reply ?? false
  }

  public func close() {
    var reply: Bool?
    waitReply(timeoutNil: &reply) { done in
      self.proxy.closeSession { done(true) }
    }
    surface = nil
    avInfo = nil
  }

  /// Blocking reply helper: runs `body`, waits with the standard timeout,
  /// leaves `slot` nil on timeout.
  private func waitReply<T>(
    timeoutNil slot: inout T?, _ body: (@escaping @Sendable (T?) -> Void) -> Void
  ) {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var captured: T?
    body { value in
      captured = value
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + Self.replyTimeout) == .success else { return }
    slot = captured
  }

  private static func pack(_ width: Int, _ height: Int) -> UInt64 {
    UInt64(UInt32(clamping: width)) << 32 | UInt64(UInt32(clamping: height))
  }

  private static func unpack(_ packed: UInt64) -> (width: Int, height: Int) {
    (Int(packed >> 32), Int(packed & 0xFFFF_FFFF))
  }
}
