import Foundation

/// Catalog-style dump names ("Title, The (USA) (Rev 1)") normalized for
/// display, sorting, and matching. Pure string work: no database, no
/// network — the filename itself carries this much and no more.
public struct NormalizedTitle: Equatable, Sendable {
  /// Article restored to the front: "The Title".
  public let displayTitle: String
  /// Lowercased, article dropped — what alphabetical order should use.
  public let sortKey: String
  /// The first parenthesized group that reads as a region list, if any.
  public let region: String?
  /// Every other parenthesized/bracketed group, in order.
  public let tags: [String]
}

public enum TitleNormalizer {
  static let regionWords: Set<String> = [
    "usa", "europe", "japan", "world", "australia", "canada", "france", "germany",
    "italy", "spain", "netherlands", "sweden", "norway", "denmark", "finland",
    "korea", "china", "asia", "brazil", "uk", "russia", "taiwan", "hong kong",
  ]

  static let articles = ["The", "A", "An"]

  public static func normalize(filename: String) -> NormalizedTitle {
    var base = filename
    var groups: [String] = []

    // Peel trailing (...) and [...] groups; anything before the first group
    // is the title proper.
    while true {
      let trimmed = base.trimmingCharacters(in: .whitespaces)
      guard let open = trimmed.lastIndex(where: { $0 == "(" || $0 == "[" }) else { break }
      let closer: Character = trimmed[open] == "(" ? ")" : "]"
      guard trimmed.hasSuffix(String(closer)), trimmed.index(after: open) < trimmed.endIndex
      else { break }
      let inner = String(
        trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
      groups.insert(inner.trimmingCharacters(in: .whitespaces), at: 0)
      base = String(trimmed[..<open])
    }
    base = base.trimmingCharacters(in: .whitespaces)

    var region: String?
    var tags: [String] = []
    for group in groups {
      if region == nil, isRegionList(group) {
        region = group
      } else {
        tags.append(group)
      }
    }

    let (display, sortBase) = flipArticle(base)
    return NormalizedTitle(
      displayTitle: display, sortKey: sortBase.lowercased(), region: region, tags: tags)
  }

  /// "Legend of Zelda, The" → ("The Legend of Zelda", "Legend of Zelda").
  static func flipArticle(_ base: String) -> (display: String, sortBase: String) {
    for article in articles {
      let suffix = ", " + article
      if base.hasSuffix(suffix), base.count > suffix.count {
        let stem = String(base.dropLast(suffix.count))
        return (article + " " + stem, stem)
      }
    }
    return (base, base)
  }

  static func isRegionList(_ group: String) -> Bool {
    let parts = group.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }
    guard !parts.isEmpty else { return false }
    return parts.allSatisfy { regionWords.contains($0) }
  }
}
