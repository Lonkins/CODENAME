import CryptoKit
import Foundation

/// User-supplied PlayStation BIOS handling (ADR 0007): recognize files by
/// digest — names in the wild vary hopelessly — and stage verified images
/// under the canonical filenames cores actually look for in the system
/// directory root. No BIOS data or acquisition guidance lives here: digests
/// identify what the user already legally owns.
public enum PSXBIOS {
  public struct Image: Equatable, Sendable {
    public let canonicalName: String
    public let region: String
  }

  /// MD5 → canonical image, as documented by the libretro Beetle PSX manual.
  public static let known: [String: Image] = [
    "8dd7d5296a650fac7319bce665a6a53c": Image(canonicalName: "scph5500.bin", region: "Japan"),
    "490f666e1afb15b7362b406ed1cea246": Image(canonicalName: "scph5501.bin", region: "America"),
    "32736f17079d0b2b7024407c39bd3050": Image(canonicalName: "scph5502.bin", region: "Europe"),
  ]

  /// Anything plausibly a BIOS image is this small; larger files are never
  /// hashed (cheap guard against pointing the importer at disc images).
  static let maxImageBytes = 4 * 1024 * 1024

  public struct StageReport: Equatable, Sendable {
    public var staged: [Image] = []
    public var alreadyPresent: [Image] = []
    public var missingRegions: [String] = []
  }

  public static func recognize(_ url: URL) -> Image? {
    guard
      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size <= maxImageBytes,
      let data = try? Data(contentsOf: url)
    else { return nil }
    let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return known[digest]
  }

  /// Copies every recognized file into `systemDirectory` under its
  /// canonical name (existing files are left untouched — the user's system
  /// directory is theirs). Reports what's still missing by region.
  public static func stage(files: [URL], into systemDirectory: URL) -> StageReport {
    var report = StageReport()
    var present = Set<String>()

    for url in files {
      guard let image = PSXBIOS.recognize(url) else { continue }
      guard !present.contains(image.canonicalName) else { continue }
      let destination = systemDirectory.appendingPathComponent(image.canonicalName)
      if FileManager.default.fileExists(atPath: destination.path) {
        report.alreadyPresent.append(image)
        present.insert(image.canonicalName)
        continue
      }
      guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { continue }
      report.staged.append(image)
      present.insert(image.canonicalName)
    }

    // Missing = not on disk after staging, whatever the source: canonical
    // files the user placed there by hand count as present.
    report.missingRegions = known.values
      .filter {
        !FileManager.default.fileExists(
          atPath: systemDirectory.appendingPathComponent($0.canonicalName).path)
      }
      .map(\.region)
      .sorted()
    return report
  }
}
