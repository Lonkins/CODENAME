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

  /// Filename → entry match, case-insensitive, tolerant of catalog-style
  /// decorations on either side: an image named like the dump ("Title, The
  /// (USA).png") matches an entry displaying the normalized title, and vice
  /// versa. Returns how many entries gained artwork.
  @discardableResult
  public func importMatching(folder: URL, entries: [GameEntry]) -> Int {
    let images = LibraryScanner.scan(root: folder, extensions: ["png", "jpg", "jpeg", "heic"])
    var byKey: [String: UUID] = [:]
    for entry in entries {
      let rawBase = (entry.relativePath as NSString).lastPathComponent
      for key in Self.matchKeys(rawBase.isEmpty ? entry.displayName : rawBase)
        + Self.matchKeys(entry.displayName)
      {
        byKey[key] = byKey[key] ?? entry.id
      }
    }
    var imported = 0
    for image in images {
      guard let entryID = Self.matchKeys(image.displayName).compactMap({ byKey[$0] }).first
      else { continue }
      let sourceURL = folder.appendingPathComponent(image.relativePath)
      if (try? setArtwork(from: sourceURL, for: entryID)) != nil {
        imported += 1
      }
    }
    return imported
  }

  /// Both the literal name and its normalized title, lowercased.
  static func matchKeys(_ filename: String) -> [String] {
    let base = (filename as NSString).deletingPathExtension
    let normalized = TitleNormalizer.normalize(filename: base).displayTitle.lowercased()
    let literal = base.lowercased()
    return normalized == literal ? [literal] : [literal, normalized]
  }

  private func url(for entryID: UUID) -> URL {
    directory.appendingPathComponent(entryID.uuidString + ".png")
  }
}
