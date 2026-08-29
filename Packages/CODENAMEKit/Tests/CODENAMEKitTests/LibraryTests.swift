import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct LibraryStoreTests {
  private let store = LibraryStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("lib-\(UUID().uuidString)", isDirectory: true))

  @Test func emptyWhenNoFile() {
    #expect(store.load() == Library())
  }

  @Test func roundTripsLibrary() throws {
    var library = Library()
    library.entries.append(
      GameEntry(
        id: UUID(), sourceID: nil, relativePath: "/tmp/game.sfc", bookmark: Data([1, 2]),
        displayName: "Game", coreID: "snes9x_libretro", addedAt: Date(timeIntervalSince1970: 5),
        lastPlayedAt: nil))
    library.sources.append(LibrarySource(id: UUID(), bookmark: Data([3]), name: "Folder"))
    try store.save(library)
    #expect(store.load() == library)
  }
}

@MainActor
@Suite struct LibraryModelTests {
  private func makeModel() -> LibraryModel {
    LibraryModel(
      store: LibraryStore(
        directory: FileManager.default.temporaryDirectory
          .appendingPathComponent("libm-\(UUID().uuidString)", isDirectory: true)))
  }

  @Test func recordPlayUpsertsByPathAndCore() {
    let model = makeModel()
    model.recordPlay(path: "/a/game.sfc", displayName: "game", coreID: "snes9x", bookmark: nil)
    model.recordPlay(path: "/a/game.sfc", displayName: "game", coreID: "snes9x", bookmark: nil)
    #expect(model.library.entries.count == 1)

    model.recordPlay(path: "/a/game.md", displayName: "game", coreID: "genesis", bookmark: nil)
    #expect(model.library.entries.count == 2)
  }

  @Test func recentsOrderedByLastPlayedAndCapped() {
    let model = makeModel()
    for index in 0..<15 {
      model.recordPlay(
        path: "/g/\(index).sfc", displayName: "\(index)", coreID: "c", bookmark: nil,
        at: Date(timeIntervalSince1970: Double(index)))
    }
    let recents = model.recents(limit: 10)
    #expect(recents.count == 10)
    #expect(recents.first?.displayName == "14")
    #expect(recents.last?.displayName == "5")
  }

  @Test func persistsAcrossInstances() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("libp-\(UUID().uuidString)", isDirectory: true)
    let first = LibraryModel(store: LibraryStore(directory: directory))
    first.recordPlay(path: "/x.sfc", displayName: "x", coreID: "c", bookmark: Data([7]))

    let second = LibraryModel(store: LibraryStore(directory: directory))
    #expect(second.library.entries.count == 1)
    #expect(second.library.entries.first?.bookmark == Data([7]))
  }
}
