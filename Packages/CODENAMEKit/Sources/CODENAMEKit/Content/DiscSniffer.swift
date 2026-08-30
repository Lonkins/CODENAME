import Foundation

/// Disc extensions are ambiguous — `.cue` is PlayStation, Sega CD, PC
/// Engine CD and more, and several cores advertise it. The disc itself
/// says what it is (ADR 0007): identification strings live in the first
/// sectors of track 1.
public enum DiscSniffer {
  public enum System: Equatable, Sendable {
    case playStation
    case segaCD
    case unknown
  }

  static let windowBytes = 128 * 1024

  /// Follows a cue sheet to its first referenced file and sniffs that;
  /// sniffs any other file directly.
  public static func identify(contentURL: URL) -> System {
    guard contentURL.pathExtension.lowercased() == "cue" else {
      return identify(dataFileURL: contentURL)
    }
    guard let cueText = try? String(contentsOf: contentURL, encoding: .utf8),
      let first = LibraryScanner.cueReferencedFiles(cueText).first
    else { return .unknown }
    return identify(
      dataFileURL: contentURL.deletingLastPathComponent().appendingPathComponent(first))
  }

  static func identify(dataFileURL: URL) -> System {
    guard let handle = try? FileHandle(forReadingFrom: dataFileURL),
      let data = try? handle.read(upToCount: windowBytes)
    else { return .unknown }
    try? handle.close()
    if data.firstRange(of: Data("SEGADISCSYSTEM".utf8)) != nil { return .segaCD }
    if data.firstRange(of: Data("PLAYSTATION".utf8)) != nil
      || data.firstRange(of: Data("Sony Computer Entertainment".utf8)) != nil
    {
      return .playStation
    }
    return .unknown
  }
}
