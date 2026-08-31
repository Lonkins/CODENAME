import Foundation

/// Structural gate run before `dlopen` (ADR 0001): cheap facts about the
/// file itself, checked in the process that is about to load it. It proves
/// nothing about trustworthiness — that is the trust policy's job and, in
/// signed builds, the kernel's — but it keeps files that are plainly not
/// cores away from the dynamic linker.
public enum MachOImage {
  /// Comfortably above the largest core we ship (Beetle PSX is ~16MB) and
  /// far below anything that belongs in a dlopen call.
  public static let maxImageBytes = 256 * 1024 * 1024

  /// Mach-O and universal-binary magic as they appear at offset 0.
  private static let magics: Set<[UInt8]> = [
    [0xCF, 0xFA, 0xED, 0xFE],  // MH_MAGIC_64, little-endian on disk
    [0xFE, 0xED, 0xFA, 0xCF],  // MH_CIGAM_64
    [0xCA, 0xFE, 0xBA, 0xBE],  // FAT_MAGIC
    [0xCA, 0xFE, 0xBA, 0xBF],  // FAT_MAGIC_64
  ]

  public static func isLoadable(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue,
      let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
      size > 0, size <= maxImageBytes,
      let handle = try? FileHandle(forReadingFrom: url)
    else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
    return magics.contains([UInt8](head))
  }
}
