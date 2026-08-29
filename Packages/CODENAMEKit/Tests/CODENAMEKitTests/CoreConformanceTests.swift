import CryptoKit
import Foundation
import Testing

@testable import CODENAMEKit

// User-supplied, never in the repo or CI: CONFORMANCE_CORE_PATH (dylib) and
// CONFORMANCE_CONTENT_PATH (content file). Optional: CONFORMANCE_FRAMES
// (default 300), CONFORMANCE_EXPECTED_HASH (asserts the framebuffer digest).
// Run alone (swift test --filter CoreConformanceTests): sessions are
// process-exclusive, so this suite must not race CoreSessionTests.
private let corePath = ProcessInfo.processInfo.environment["CONFORMANCE_CORE_PATH"]
private let contentPath = ProcessInfo.processInfo.environment["CONFORMANCE_CONTENT_PATH"]

@Suite(.serialized, .enabled(if: corePath != nil && contentPath != nil))
struct CoreConformanceTests {
  private var frames: Int {
    ProcessInfo.processInfo.environment["CONFORMANCE_FRAMES"].flatMap(Int.init) ?? 300
  }

  private func makeSession() throws -> CoreSession {
    let coreURL = URL(fileURLWithPath: corePath ?? "/nonexistent")
    let environment = EnvironmentHandler(
      systemDirectory: FileManager.default.temporaryDirectory,
      saveDirectory: FileManager.default.temporaryDirectory)
    return try CoreSession(
      coreURL: coreURL,
      policy: CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent()),
      environment: environment)
  }

  private func hash(_ frame: CoreSession.VideoFrame) -> String {
    SHA256.hash(data: Data(frame.bytes)).map { String(format: "%02x", $0) }.joined()
  }

  @Test func framebufferHashAfterNFrames() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: contentPath)

    session.run(frames: frames)
    _ = session.drainAudioSamples()
    let frame = try #require(session.latestFrame)
    let digest = hash(frame)
    print("conformance: \(frames) frames -> \(digest)")

    if let expected = ProcessInfo.processInfo.environment["CONFORMANCE_EXPECTED_HASH"] {
      #expect(digest == expected)
    }
  }

  @Test func saveStateRoundTripIsDeterministic() throws {
    let session = try makeSession()
    defer { session.shutdown() }
    try session.loadGame(path: contentPath)

    session.run(frames: frames / 2)
    let snapshot = try session.serialize()

    session.run(frames: 30)
    _ = session.drainAudioSamples()
    let firstRun = try #require(session.latestFrame)
    let firstHash = hash(firstRun)

    try session.unserialize(snapshot)
    session.run(frames: 30)
    let secondRun = try #require(session.latestFrame)
    #expect(hash(secondRun) == firstHash)
  }
}
