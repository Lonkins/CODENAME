import Foundation
import Testing

@testable import CODENAMEKit

// Each suite file declares its own, as the other core-backed suites do.
private let testCorePath = ProcessInfo.processInfo.environment["TEST_CORE_PATH"]

/// TestCore declares one option and echoes its resolved value into pixel 2 of
/// every frame, the same channel it uses for input. That makes "the core
/// actually read what the frontend holds" observable rather than assumed.
@Suite(.serialized, .enabled(if: testCorePath != nil))
struct CoreOptionEchoTests {
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }

  private func makeSession(seeding options: [String: String]) throws -> (
    session: CoreSession, environment: EnvironmentHandler
  ) {
    let environment = EnvironmentHandler(
      systemDirectory: FileManager.default.temporaryDirectory,
      saveDirectory: FileManager.default.temporaryDirectory)
    environment.options.prefer(options)
    let session = try CoreSession(
      coreURL: coreURL,
      policy: CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent()),
      environment: environment)
    return (session, environment)
  }

  /// RGB565: pixel 2 occupies bytes 4 and 5, little-endian.
  private func echo(_ session: CoreSession) throws -> UInt16 {
    let frame = try #require(session.latestFrame)
    return UInt16(frame.bytes[4]) | (UInt16(frame.bytes[5]) << 8)
  }

  @Test func aCoreWithNoStoredSelectionReadsItsDeclaredDefault() throws {
    let (session, _) = try makeSession(seeding: [:])
    defer { session.shutdown() }
    try session.loadGame(path: nil)
    session.run(frames: 1)
    #expect(try echo(session) == 0)
  }

  @Test func aStoredSelectionReachesTheCoreThroughTheABI() throws {
    let (session, _) = try makeSession(seeding: ["testcore_echo": "7"])
    defer { session.shutdown() }
    try session.loadGame(path: nil)
    session.run(frames: 1)
    #expect(try echo(session) == 7)
  }

  @Test func aChangeMidSessionReachesTheCoreOnTheNextFrame() throws {
    // Exercises the update flag the whole way round: the core only re-reads
    // because the frontend told it something changed.
    let (session, environment) = try makeSession(seeding: [:])
    defer { session.shutdown() }
    try session.loadGame(path: nil)
    session.run(frames: 1)
    #expect(try echo(session) == 0)

    environment.options.setValue("9", for: "testcore_echo")
    session.run(frames: 1)
    #expect(try echo(session) == 9)
  }
}

/// The same contract across the process boundary: a helper-hosted core must
/// resolve options exactly as an in-process one does, and the app must be able
/// to read back what the core declared.
@Suite(.serialized, .enabled(if: testCorePath != nil))
struct HelperCoreOptionsTests {
  private var coreURL: URL { URL(fileURLWithPath: testCorePath ?? "/nonexistent") }
  private var temporary: String { FileManager.default.temporaryDirectory.path }

  private func openedSession(options: [String: String]) throws -> HelperSession {
    let host = LoopbackCoreHost()
    let proxy = try #require(host.proxy(errorHandler: { _ in }))
    let session = HelperSession(proxy: proxy)
    let opened = session.open(
      corePath: coreURL.path, contentPath: nil, systemDirectory: temporary,
      saveDirectory: temporary, options: options)
    _ = try #require(opened)
    return session
  }

  @Test func aCoreWithNoStoredSelectionReportsItsDeclaredDefault() throws {
    let session = try openedSession(options: [:])
    defer { session.close() }
    let snapshot = try #require(session.optionsSnapshot())
    #expect(snapshot.options.map(\.key) == ["testcore_echo"])
    #expect(snapshot.selected["testcore_echo"] == "0")
  }

  @Test func aSeededSelectionReachesTheHelperHostedCore() throws {
    let session = try openedSession(options: ["testcore_echo": "7"])
    defer { session.close() }
    let snapshot = try #require(session.optionsSnapshot())
    #expect(snapshot.selected["testcore_echo"] == "7")
  }

  @Test func aSeededSelectionTheCoreDoesNotOfferFallsBackToItsDefault() throws {
    let session = try openedSession(options: ["testcore_echo": "999"])
    defer { session.close() }
    let snapshot = try #require(session.optionsSnapshot())
    #expect(snapshot.selected["testcore_echo"] == "0")
  }

  @Test func theDeclaredOptionSurvivesTheBoundaryIntact() throws {
    let session = try openedSession(options: [:])
    defer { session.close() }
    let snapshot = try #require(session.optionsSnapshot())
    let option = try #require(snapshot.options.first)
    #expect(option.title == "Echo value")
    #expect(option.values.map(\.value) == ["0", "7", "9"])
  }
}
