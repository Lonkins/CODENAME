import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// User-supplied cover art, normalized at the boundary (ADR 0001 amendment
/// hygiene: size caps, real decode, re-encode — arbitrary files are never
/// stored). Acquisition stays user-driven; network scraping is
/// helper-or-never per ADR 0001.
public struct ArtworkStore {
  public enum ArtworkError: Error {
    case notAnImage
    case tooLarge
  }

  public let directory: URL
  private let maxSourceBytes: Int
  private let thumbnailMaxPixels: Int

  public init(
    directory: URL = AppPaths.base.appendingPathComponent("Artwork"),
    maxSourceBytes: Int = 20 * 1024 * 1024,
    thumbnailMaxPixels: Int = 512
  ) {
    self.directory = directory
    self.maxSourceBytes = maxSourceBytes
    self.thumbnailMaxPixels = thumbnailMaxPixels
  }

  public func artworkURL(for entryID: UUID) -> URL? {
    let url = url(for: entryID)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  public func setArtwork(from sourceURL: URL, for entryID: UUID) throws {
    let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
    if let size = attributes?[.size] as? Int, size > maxSourceBytes {
      throw ArtworkError.tooLarge
    }
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else { throw ArtworkError.notAnImage }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw ArtworkError.notAnImage }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = url(for: entryID)
    guard
      let destination = CGImageDestinationCreateWithURL(
        target as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw ArtworkError.notAnImage }
    CGImageDestinationAddImage(destination, thumbnail, nil)
    guard CGImageDestinationFinalize(destination) else { throw ArtworkError.notAnImage }
  }

  public func removeArtwork(for entryID: UUID) {
    try? FileManager.default.removeItem(at: url(for: entryID))
  }

  /// Filename (minus extension, case-insensitive) → entry displayName match.
  /// Returns how many entries gained artwork.
  @discardableResult
  public func importMatching(folder: URL, entries: [GameEntry]) -> Int {
    let images = LibraryScanner.scan(root: folder, extensions: ["png", "jpg", "jpeg", "heic"])
    let byName = Dictionary(
      entries.map { ($0.displayName.lowercased(), $0.id) }, uniquingKeysWith: { first, _ in first })
    var imported = 0
    for image in images {
      guard let entryID = byName[image.displayName.lowercased()] else { continue }
      let sourceURL = folder.appendingPathComponent(image.relativePath)
      if (try? setArtwork(from: sourceURL, for: entryID)) != nil {
        imported += 1
      }
    }
    return imported
  }

  private func url(for entryID: UUID) -> URL {
    directory.appendingPathComponent(entryID.uuidString + ".png")
  }
}
