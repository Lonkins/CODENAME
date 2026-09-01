import Foundation

/// Hands disc content to a process that cannot open it by path.
///
/// Cartridge content crosses as bytes, but a disc image is hundreds of
/// megabytes and a `need_fullpath` core opens sibling track files itself,
/// by the names written inside the cue. So the sender opens those files and
/// passes the descriptors; the receiver builds a staging directory in its
/// own container where every referenced name is a symlink to `/dev/fd/N`
/// and the cue is copied verbatim — its relative `FILE` lines then resolve
/// to the symlinks, and the core opens exactly what the sender granted.
public enum DiscStaging {
  /// What travels alongside the descriptors (JSON on the wire).
  public struct Payload: Codable, Equatable, Sendable {
    /// Leaf name of the content the core is asked to load.
    public let name: String
    /// Verbatim cue text, or nil when the content is a single file.
    public let cueText: String?
    /// Names to stage, in the same order as the descriptors.
    public let referencedNames: [String]
  }

  public struct Handoff: Sendable {
    public let payload: Payload
    /// The files to open, in `referencedNames` order.
    public let files: [URL]
  }

  /// Enough for every BIOS set a core asks for, far below any descriptor
  /// limit worth worrying about.
  public static let maxStagedFiles = 64

  public enum Failure: Error, Equatable {
    case unreadableContent(String)
    case missingTrack(String)
    case descriptorCountMismatch(expected: Int, received: Int)
  }

  /// Sender side: what to open and what to send.
  public static func prepare(contentAt url: URL) throws(Failure) -> Handoff {
    let name = url.lastPathComponent
    guard url.pathExtension.lowercased() == "cue" else {
      return Handoff(
        payload: Payload(name: name, cueText: nil, referencedNames: [name]), files: [url])
    }
    guard let cueText = try? String(contentsOf: url, encoding: .utf8) else {
      throw .unreadableContent(name)
    }
    let names = LibraryScanner.cueReferencedFiles(cueText)
    let directory = url.deletingLastPathComponent()
    var files: [URL] = []
    for referenced in names {
      let track = directory.appendingPathComponent(referenced)
      guard FileManager.default.fileExists(atPath: track.path) else {
        throw .missingTrack(referenced)
      }
      files.append(track)
    }
    return Handoff(
      payload: Payload(name: name, cueText: cueText, referencedNames: names), files: files)
  }

  /// Sender side for a whole directory the receiver cannot read — BIOS
  /// images reach cores through `GET_SYSTEM_DIRECTORY`, which points into
  /// the app's container. Regular files only, sorted so the descriptor
  /// order is deterministic, and bounded: a core needs a handful of BIOS
  /// images, not an unbounded descriptor table.
  public static func prepareDirectory(at url: URL) throws(Failure) -> Handoff {
    let listing =
      (try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
    let files =
      listing
      .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .prefix(maxStagedFiles)
    return Handoff(
      payload: Payload(
        name: "", cueText: nil, referencedNames: files.map(\.lastPathComponent)),
      files: Array(files))
  }

  /// Receiver side: write a core the sender read but must never load, so it
  /// can be opened from a directory this process actually owns. The name is
  /// taken as a leaf only — a sender does not get to choose the location.
  public static func stageCore(
    named name: String, bytes: Data, in directory: URL
  ) throws(Failure) -> URL {
    let leaf = (name as NSString).lastPathComponent
    guard !bytes.isEmpty, leaf == name, !leaf.isEmpty, leaf != ".", leaf != ".." else {
      throw .unreadableContent(name)
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(leaf)
      try bytes.write(to: destination, options: .atomic)
      // dyld maps the image executable; a plain 0644 write is not enough.
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: destination.path)
      return destination
    } catch {
      throw .unreadableContent(name)
    }
  }

  /// Receiver side: rebuild the content in `directory` from the descriptors.
  /// Returns the path to hand the core — the staged file, or the directory
  /// itself when the payload names no single one.
  public static func materialize(
    _ payload: Payload, descriptors: [Int32], in directory: URL
  ) throws(Failure) -> URL {
    guard descriptors.count == payload.referencedNames.count else {
      throw .descriptorCountMismatch(
        expected: payload.referencedNames.count, received: descriptors.count)
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (referenced, descriptor) in zip(payload.referencedNames, descriptors) {
        let link = directory.appendingPathComponent(referenced)
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
          at: link, withDestinationURL: URL(fileURLWithPath: "/dev/fd/\(descriptor)"))
      }
      if let cueText = payload.cueText {
        try Data(cueText.utf8).write(to: directory.appendingPathComponent(payload.name))
      }
    } catch {
      throw .unreadableContent(payload.name)
    }
    return payload.name.isEmpty ? directory : directory.appendingPathComponent(payload.name)
  }
}
