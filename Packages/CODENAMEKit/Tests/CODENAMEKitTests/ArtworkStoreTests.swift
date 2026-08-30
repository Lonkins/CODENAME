import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CODENAMEKit

private func writeTestPNG(to url: URL, width: Int = 64, height: Int = 48) throws {
  guard
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw ArtworkStore.ArtworkError.notAnImage }
  context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw ArtworkStore.ArtworkError.notAnImage }
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
}

@Suite struct ArtworkStoreTests {
  private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("art-\(UUID().uuidString)", isDirectory: true)
  private var store: ArtworkStore {
    ArtworkStore(directory: root.appendingPathComponent("Artwork"))
  }

  init() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  @Test func importMatchesDumpNamedArtToNormalizedEntry() throws {
    // Entry displays the normalized title; the art folder uses full dump
    // names — they must still pair up.
    let folder = root.appendingPathComponent("art-in", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try writeTestPNG(to: folder.appendingPathComponent("Zelda, The (USA) (Rev 1).png"))
    let entry = GameEntry(
      id: UUID(), sourceID: nil, relativePath: "Zelda, The (USA) (Rev 1).sfc", bookmark: nil,
      displayName: "The Zelda", coreID: "snes9x", addedAt: .now, lastPlayedAt: nil)
    #expect(store.importMatching(folder: folder, entries: [entry]) == 1)
    #expect(store.artworkURL(for: entry.id) != nil)
  }

  @Test func importsAndNormalizesImage() throws {
    let source = root.appendingPathComponent("cover.png")
    try writeTestPNG(to: source, width: 1200, height: 900)
    let id = UUID()
    try store.setArtwork(from: source, for: id)

    let stored = try #require(store.artworkURL(for: id))
    let imageSource = try #require(CGImageSourceCreateWithURL(stored as CFURL, nil))
    let properties =
      CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    #expect(width <= 512)
    #expect(width > 0)
  }

  @Test func rejectsNonImages() throws {
    let junk = root.appendingPathComponent("junk.png")
    try Data("not an image".utf8).write(to: junk)
    #expect(throws: (any Error).self) {
      try store.setArtwork(from: junk, for: UUID())
    }
    #expect(store.artworkURL(for: UUID()) == nil)
  }

  @Test func removeDeletesArtwork() throws {
    let source = root.appendingPathComponent("a.png")
    try writeTestPNG(to: source)
    let id = UUID()
    try store.setArtwork(from: source, for: id)
    store.removeArtwork(for: id)
    #expect(store.artworkURL(for: id) == nil)
  }

  @Test func folderImportMatchesByDisplayName() throws {
    let folder = root.appendingPathComponent("covers", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try writeTestPNG(to: folder.appendingPathComponent("Sonic The Hedgehog.png"))
    try writeTestPNG(to: folder.appendingPathComponent("UNRELATED.png"))

    let sonic = GameEntry(
      id: UUID(), sourceID: nil, relativePath: "s.md", bookmark: nil,
      displayName: "sonic the hedgehog", coreID: "g", addedAt: Date(), lastPlayedAt: nil)
    let mario = GameEntry(
      id: UUID(), sourceID: nil, relativePath: "m.sfc", bookmark: nil,
      displayName: "Super Mario World", coreID: "s", addedAt: Date(), lastPlayedAt: nil)

    let imported = store.importMatching(folder: folder, entries: [sonic, mario])
    #expect(imported == 1)
    #expect(store.artworkURL(for: sonic.id) != nil)
    #expect(store.artworkURL(for: mario.id) == nil)
  }
}
