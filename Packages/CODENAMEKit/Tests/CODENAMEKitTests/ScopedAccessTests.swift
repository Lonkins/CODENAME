import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct BookmarkTests {
  @Test func plainBookmarkRoundTrips() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("bookmark-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)

    // Security-scoped options need a sandboxed process; tests exercise the
    // same path with plain bookmarks (option injection).
    let data = try Bookmark.create(for: file, securityScoped: false)
    let resolved = try Bookmark.resolve(data, securityScoped: false)
    #expect(resolved.url.standardizedFileURL.path == file.standardizedFileURL.path)
    #expect(resolved.isStale == false)
  }

  @Test func resolvingGarbageThrows() {
    #expect(throws: (any Error).self) {
      _ = try Bookmark.resolve(Data([0x00, 0x01]), securityScoped: false)
    }
  }

  @Test func scopedAccessHoldsURLAndSurvivesUnsandboxedProcess() {
    let access = ScopedAccess(url: FileManager.default.temporaryDirectory)
    #expect(access.url == FileManager.default.temporaryDirectory)
  }
}
