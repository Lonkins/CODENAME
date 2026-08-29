import Testing

@testable import CODENAMEKit

@Suite struct SemanticVersionTests {
  @Test func parsesDottedTriple() throws {
    let v = try #require(SemanticVersion("1.2.3"))
    #expect(v.major == 1)
    #expect(v.minor == 2)
    #expect(v.patch == 3)
  }

  @Test(arguments: ["", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "-1.2.3", "1..3", " 1.2.3"])
  func rejectsMalformed(_ raw: String) {
    #expect(SemanticVersion(raw) == nil)
  }

  @Test func ordersNumericallyNotLexically() throws {
    let a = try #require(SemanticVersion("0.9.0"))
    let b = try #require(SemanticVersion("0.10.0"))
    #expect(a < b)
  }

  @Test func comparesAcrossComponents() throws {
    let ordered = ["0.0.9", "0.1.0", "0.1.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"]
      .compactMap(SemanticVersion.init)
    #expect(ordered.count == 7)
    #expect(ordered == ordered.sorted())
  }

  @Test func equalityAndDescription() throws {
    let v = try #require(SemanticVersion("1.2.3"))
    #expect(v == SemanticVersion("1.2.3"))
    #expect(v.description == "1.2.3")
  }
}
