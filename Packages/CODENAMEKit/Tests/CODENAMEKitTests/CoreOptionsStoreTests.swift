import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct CoreOptionsStoreTests {
  private let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("options-\(UUID().uuidString)", isDirectory: true)

  private var url: URL { directory.appendingPathComponent("core.json") }

  @Test func savedValuesLoadBack() throws {
    try CoreOptionsStore.save(["psx_renderer": "hardware"], to: url)
    #expect(try CoreOptionsStore.load(from: url) == ["psx_renderer": "hardware"])
  }

  @Test func missingFileLoadsAsNoSelections() throws {
    #expect(try CoreOptionsStore.load(from: url).isEmpty)
  }

  @Test func unreadableFileLoadsAsNoSelections() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(try CoreOptionsStore.load(from: url).isEmpty)
  }

  @Test func savingCreatesTheDirectory() throws {
    // The store is asked for a path before anything guarantees it exists.
    try CoreOptionsStore.save(["k": "v"], to: url)
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test func savingKeepsSelectionsTheCoreDidNotDeclareThisTime() throws {
    // Cores may declare a different option set per content; rewriting the file
    // from one session's set alone would silently drop the rest.
    try CoreOptionsStore.save(["shared": "a", "gb_only": "on"], to: url)
    try CoreOptionsStore.save(["shared": "b"], to: url)
    #expect(try CoreOptionsStore.load(from: url) == ["shared": "b", "gb_only": "on"])
  }
}

@Suite struct CoreOptionsPreferenceTests {
  private func option(_ key: String, _ values: [String], default defaultValue: String) -> CoreOption
  {
    CoreOption(
      key: key, title: key, values: values.map { CoreOptionValue(value: $0) },
      defaultValue: defaultValue)
  }

  @Test func aStoredSelectionIsAppliedWhenTheCoreDeclaresIt() {
    let options = CoreOptions()
    options.prefer(["k": "b"])
    options.declare([option("k", ["a", "b"], default: "a")])
    #expect(options.value(for: "k") == "b")
  }

  @Test func aStoredSelectionTheCoreNoLongerOffersFallsBackToTheDefault() {
    let options = CoreOptions()
    options.prefer(["k": "gone"])
    options.declare([option("k", ["a", "b"], default: "a")])
    #expect(options.value(for: "k") == "a")
  }

  @Test func aStoredSelectionForAnUndeclaredKeyIsIgnored() {
    let options = CoreOptions()
    options.prefer(["other": "x"])
    options.declare([option("k", ["a"], default: "a")])
    #expect(options.value(for: "other") == nil)
  }

  @Test func anInSessionChoiceOutranksTheStoredOneOnRedeclaration() {
    // The user changed it while playing; a re-declaration must not undo that.
    let options = CoreOptions()
    options.prefer(["k": "a"])
    options.declare([option("k", ["a", "b"], default: "a")])
    options.setValue("b", for: "k")
    options.declare([option("k", ["a", "b"], default: "a")])
    #expect(options.value(for: "k") == "b")
  }

  @Test func applyingStoredSelectionsRaisesNoUpdate() {
    // Loading a session is not a change the core needs to be told about.
    let options = CoreOptions()
    options.prefer(["k": "b"])
    options.declare([option("k", ["a", "b"], default: "a")])
    #expect(!options.takeUpdateFlag())
  }

  @Test func selectedValuesReportsEveryResolvedOption() {
    let options = CoreOptions()
    options.prefer(["k": "b"])
    options.declare([option("k", ["a", "b"], default: "a"), option("j", ["x"], default: "x")])
    #expect(options.selectedValues == ["k": "b", "j": "x"])
  }
}
