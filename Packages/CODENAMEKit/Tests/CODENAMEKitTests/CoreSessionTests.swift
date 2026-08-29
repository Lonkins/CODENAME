import Foundation
import Testing

@testable import CODENAMEKit

private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

// Serialized: sessions own process-global state (the active-session slot and
// the test core's statics), so these tests must not interleave.
@Suite(.serialized, .enabled(if: testCorePath != nil))
struct CoreSessionTests {
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }
  private var policy: CoreTrustPolicy {
    CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())
  }

  private func makeSession() throws -> CoreSession {
    let environment = EnvironmentHandler(
      systemDirectory: FileManager.default.temporaryDirectory,
      saveDirectory: FileManager.default.temporaryDirectory)
    return try CoreSession(coreURL: coreURL, policy: policy, environment: environment)
  }

  @Test func loadsRunsAndProducesAV() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: nil)

    let av = try #require(session.avInfo)
    #expect(av.baseSize == CoreAVInfo.Size(width: 320, height: 240))
    #expect(av.framesPerSecond == 60.0)
    #expect(av.audioSampleRate == 44100.0)

    session.run(frames: 3)
    let frame = try #require(session.latestFrame)
    #expect(frame.width == 320)
    #expect(frame.height == 240)
    #expect(frame.pixelFormat == .rgb565)
    #expect(frame.bytes.count == frame.pitch * frame.height)
    #expect(session.audioSamples.count == 3 * 735 * 2)
  }

  @Test func frameContentAdvancesWithRuns() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: nil)

    session.run(frames: 1)
    let first = try #require(session.latestFrame)
    #expect(first.bytes[0] == 1 && first.bytes[1] == 0)

    session.run(frames: 1)
    let second = try #require(session.latestFrame)
    #expect(second.bytes[0] == 2 && second.bytes[1] == 0)
  }

  @Test func saveStateRoundTrips() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: nil)

    session.run(frames: 5)
    let snapshot = try session.serialize()
    #expect(!snapshot.isEmpty)

    session.run(frames: 3)
    try session.unserialize(snapshot)
    session.run(frames: 1)

    let frame = try #require(session.latestFrame)
    #expect(frame.bytes[0] == 6 && frame.bytes[1] == 0)
  }

  @Test func drainReturnsAndClearsAudio() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: nil)

    session.run(frames: 2)
    let drained = session.drainAudioSamples()
    #expect(drained.count == 2 * 735 * 2)
    #expect(session.drainAudioSamples().isEmpty)

    session.run(frames: 1)
    #expect(session.drainAudioSamples().count == 735 * 2)
  }

  @Test func rejectsHardwareRenderCores() throws {
    setenv("TEST_CORE_REQUEST_HW", "1", 1)
    defer { unsetenv("TEST_CORE_REQUEST_HW") }

    let session = try makeSession()
    defer { session.shutdown() }
    #expect(throws: CoreSession.SessionError.hardwareRenderUnsupported) {
      try session.loadGame(path: nil)
    }
  }

  @Test func refusesSecondActiveSession() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    #expect(throws: CoreSession.SessionError.alreadyActive) {
      _ = try makeSession()
    }
  }

  @Test func shutdownFreesTheActiveSlot() throws {
    let first = try makeSession()
    first.shutdown()
    let second = try makeSession()
    second.shutdown()
  }
}
