import Foundation
import IOSurface
import Testing

@testable import CODENAMEKit

private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

// The app-side client the helper display loop drives — proven over the same
// loopback NSXPC machinery as the raw protocol (ADR 0006 verification
// strategy). Serialized: sessions are process-exclusive.
@Suite(.serialized, .enabled(if: testCorePath != nil))
struct HelperSessionTests {
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }

  private func openSession(_ host: LoopbackCoreHost) throws -> HelperSession {
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let session = HelperSession(proxy: proxy)
    session.bind(connection: host.clientConnection)
    let av = session.open(
      corePath: coreURL.path, contentPath: nil,
      systemDirectory: FileManager.default.temporaryDirectory.path,
      saveDirectory: FileManager.default.temporaryDirectory.path)
    #expect(av != nil)
    return session
  }

  @Test func opensAndSizesSurfaceFromMaxGeometry() throws {
    let host = LoopbackCoreHost()
    let session = try openSession(host)
    defer { session.close() }

    let av = try #require(session.avInfo)
    #expect(av.baseWidth == 320)
    #expect(av.baseHeight == 240)
    #expect(av.aspectRatio > 0)
    let surface = try #require(session.surface)
    #expect(IOSurfaceGetWidth(surface) == av.maxWidth)
    #expect(IOSurfaceGetHeight(surface) == av.maxHeight)
    #expect(session.latestFrameSize.width == av.baseWidth)
  }

  @Test func runsFramesWithInputAndDeliversAudio() throws {
    let host = LoopbackCoreHost()
    let session = try openSession(host)
    defer { session.close() }

    session.inputState.set(.b, pressed: true)
    let audioArrived = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var audioBytes = 0
    #expect(
      session.runFrame { audio in
        audioBytes = audio.count
        audioArrived.signal()
      } == .sent)
    #expect(audioArrived.wait(timeout: .now() + 10) == .success)
    #expect(audioBytes > 0)

    // TestCore echoes B into pixel 1 of the shared surface.
    let surface = try #require(session.surface)
    IOSurfaceLock(surface, [.readOnly], nil)
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let pressed = PixelConverter.toBGRA8(
      bytes: [1, 0], width: 1, height: 1, pitch: 2, format: .rgb565)
    let pixel1 = [base[4], base[5], base[6], base[7]]
    IOSurfaceUnlock(surface, [.readOnly], nil)
    #expect(pixel1 == pressed)
    #expect(session.latestFrameSize == (320, 240))
  }

  @Test func saveStateAndSaveRAMRoundTrip() throws {
    let host = LoopbackCoreHost()
    let session = try openSession(host)
    defer { session.close() }

    for _ in 0..<5 {
      let done = DispatchSemaphore(value: 0)
      #expect(session.runFrame { _ in done.signal() } == .sent)
      #expect(done.wait(timeout: .now() + 10) == .success)
    }

    let state = try #require(session.serializeState())
    #expect(!state.isEmpty)
    #expect(session.unserializeState(state))

    let sram = try #require(session.saveRAMSnapshot())
    #expect(sram[0] == 5)
    var mutated = sram
    mutated[0] = 77
    #expect(session.restoreSaveRAM(mutated))
    let replayed = try #require(session.saveRAMSnapshot())
    #expect(replayed[0] == 77)
  }

  @Test func openFailureYieldsNil() throws {
    let host = LoopbackCoreHost()
    let maybeProxy = host.proxy(errorHandler: { _ in })
    let proxy = try #require(maybeProxy)
    let session = HelperSession(proxy: proxy)
    let av = session.open(
      corePath: "/usr/lib/libz.dylib", contentPath: nil,
      systemDirectory: FileManager.default.temporaryDirectory.path,
      saveDirectory: FileManager.default.temporaryDirectory.path)
    #expect(av == nil)
    #expect(session.surface == nil)
  }

  // MARK: - The helper going away (ADR 0006: "session died" is recoverable)

  @Test func aDeadHelperIsReportedInsteadOfFreezingTheSession() throws {
    let host = LoopbackCoreHost()
    let session = try openSession(host)
    let lost = DispatchSemaphore(value: 0)
    session.onSessionLost = { lost.signal() }

    // A frame in flight when the helper dies: its reply never runs, so the
    // in-flight guard used to stay set forever and every later frame was
    // silently refused — a window frozen on its last frame, no error.
    _ = session.runFrame { _ in }
    host.invalidate()

    #expect(lost.wait(timeout: .now() + 5) == .success)
    #expect(session.isAlive == false)
    #expect(session.runFrame { _ in } == .sessionLost)
  }

  @Test func closingADeadSessionDoesNotWaitForTheReplyTimeout() throws {
    let host = LoopbackCoreHost()
    let session = try openSession(host)
    let lost = DispatchSemaphore(value: 0)
    session.onSessionLost = { lost.signal() }
    host.invalidate()
    #expect(lost.wait(timeout: .now() + 5) == .success)

    // Closing the game window walked two 10-second timeouts (save-RAM flush,
    // then close) with the main thread blocked behind them.
    let started = Date()
    #expect(session.saveRAMSnapshot() == nil)
    session.close()
    #expect(Date().timeIntervalSince(started) < 1)
  }
}
