import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct DisplaySettingsTests {
  @Test func overrideWinsOverGlobal() {
    let global = DisplaySettings(integerScale: true)
    #expect(DisplaySettings.resolve(global: global, override: nil) == global)
    #expect(
      DisplaySettings.resolve(global: global, override: DisplaySettings(integerScale: false))
        == DisplaySettings(integerScale: false))
  }

  @Test func liveSettingsPublishAtomically() {
    let live = LiveDisplaySettings(DisplaySettings(integerScale: false))
    #expect(live.integerScale == false)
    live.integerScale = true
    #expect(live.integerScale == true)
  }

  @Test func oldLibraryJSONWithoutOverridesStillDecodes() throws {
    let old = """
      {"id":"\(UUID().uuidString)","sourceID":null,"relativePath":"a.sfc",
      "bookmark":null,"displayName":"a","coreID":"c",
      "addedAt":0,"lastPlayedAt":null}
      """.replacingOccurrences(of: "\n", with: "")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let entry = try decoder.decode(GameEntry.self, from: Data(old.utf8))
    #expect(entry.displayOverrides == nil)
    #expect(entry.displayName == "a")
  }
}
