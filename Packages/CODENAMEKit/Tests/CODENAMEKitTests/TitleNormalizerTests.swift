import Testing

@testable import CODENAMEKit

@Suite struct TitleNormalizerTests {
  @Test func plainNameFlowsThrough() {
    let title = TitleNormalizer.normalize(filename: "Sonic The Hedgehog")
    #expect(title.displayTitle == "Sonic The Hedgehog")
    #expect(title.sortKey == "sonic the hedgehog")
    #expect(title.region == nil)
    #expect(title.tags.isEmpty)
  }

  @Test func regionAndRevisionSeparate() {
    let title = TitleNormalizer.normalize(filename: "Super Mario World (USA) (Rev 1)")
    #expect(title.displayTitle == "Super Mario World")
    #expect(title.region == "USA")
    #expect(title.tags == ["Rev 1"])
  }

  @Test func multiRegionListRecognized() {
    let title = TitleNormalizer.normalize(
      filename: "Pokemon - Red Version (USA, Europe) (SGB Enhanced)")
    #expect(title.displayTitle == "Pokemon - Red Version")
    #expect(title.region == "USA, Europe")
    #expect(title.tags == ["SGB Enhanced"])
  }

  @Test func languageListIsATagNotARegion() {
    let title = TitleNormalizer.normalize(
      filename: "LEGO Star Wars - The Video Game (USA, Europe) (En,Fr,De,Es,It,Nl,Da)")
    #expect(title.region == "USA, Europe")
    #expect(title.tags == ["En,Fr,De,Es,It,Nl,Da"])
  }

  @Test func trailingArticleFlipsToFront() {
    let title = TitleNormalizer.normalize(filename: "Legend of Zelda, The (USA)")
    #expect(title.displayTitle == "The Legend of Zelda")
    #expect(title.sortKey == "legend of zelda")
    #expect(title.region == "USA")
  }

  @Test func bracketGroupsBecomeTags() {
    let title = TitleNormalizer.normalize(filename: "Some Game (Japan) [b]")
    #expect(title.region == "Japan")
    #expect(title.tags == ["b"])
  }

  @Test func parenthesesInsideTheTitleSurvive() {
    // Only TRAILING groups peel; a malformed midway group stays put.
    let title = TitleNormalizer.normalize(filename: "Game (not at end) more")
    #expect(title.displayTitle == "Game (not at end) more")
    #expect(title.tags.isEmpty)
  }

  @Test func sortKeyIgnoresArticleAndCase() {
    let a = TitleNormalizer.normalize(filename: "Adventure, The (USA)")
    let b = TitleNormalizer.normalize(filename: "adventure island (USA)")
    #expect(a.sortKey < b.sortKey)
  }
}
