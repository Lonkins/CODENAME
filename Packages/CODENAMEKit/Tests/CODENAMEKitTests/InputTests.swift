import CLibretro
import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct InputStateTests {
  @Test func pressAndReleaseReflectInDeviceQuery() {
    let state = InputState()
    #expect(state.value(forDeviceID: RetroPadButton.b.deviceID) == 0)

    state.set(.b, pressed: true)
    #expect(state.value(forDeviceID: RetroPadButton.b.deviceID) == 1)
    #expect(state.value(forDeviceID: RetroPadButton.a.deviceID) == 0)

    state.set(.b, pressed: false)
    #expect(state.value(forDeviceID: RetroPadButton.b.deviceID) == 0)
  }

  @Test func independentButtonsDoNotInterfere() {
    let state = InputState()
    state.set(.up, pressed: true)
    state.set(.start, pressed: true)
    #expect(state.value(forDeviceID: RetroPadButton.up.deviceID) == 1)
    #expect(state.value(forDeviceID: RetroPadButton.start.deviceID) == 1)
    #expect(state.value(forDeviceID: RetroPadButton.down.deviceID) == 0)
  }

  @Test func unknownDeviceIDReadsZero() {
    let state = InputState()
    #expect(state.value(forDeviceID: 900) == 0)
  }

  @Test func rawMaskRoundTripsWholeState() {
    let state = InputState()
    state.set(.a, pressed: true)
    state.set(.left, pressed: true)
    let mask = state.raw

    let mirrored = InputState()
    mirrored.replaceAll(with: mask)
    #expect(mirrored.value(forDeviceID: RetroPadButton.a.deviceID) == 1)
    #expect(mirrored.value(forDeviceID: RetroPadButton.left.deviceID) == 1)
    #expect(mirrored.value(forDeviceID: RetroPadButton.b.deviceID) == 0)

    mirrored.replaceAll(with: 0)
    #expect(mirrored.raw == 0)
  }

  @Test func deviceIDsMatchLibretroConstants() {
    #expect(RetroPadButton.b.deviceID == UInt32(RETRO_DEVICE_ID_JOYPAD_B))
    #expect(RetroPadButton.a.deviceID == UInt32(RETRO_DEVICE_ID_JOYPAD_A))
    #expect(RetroPadButton.start.deviceID == UInt32(RETRO_DEVICE_ID_JOYPAD_START))
    #expect(RetroPadButton.r3.deviceID == UInt32(RETRO_DEVICE_ID_JOYPAD_R3))
  }
}

@Suite struct ButtonMappingTests {
  @Test func defaultMapsNintendoLayoutAndKeyboard() {
    let mapping = ButtonMapping.defaultMapping
    #expect(mapping.pad["buttonA"] == .b)
    #expect(mapping.pad["buttonB"] == .a)
    #expect(mapping.pad["dpadUp"] == .up)
    #expect(mapping.button(forPad: "menu") == .start)
    #expect(mapping.button(forPad: "unknown") == nil)
  }

  @Test func detectsConflictingAssignments() {
    var mapping = ButtonMapping.defaultMapping
    #expect(mapping.conflicts().isEmpty)

    mapping.pad["buttonB"] = .b  // now both buttonA and buttonB → .b
    let conflicts = mapping.conflicts()
    #expect(conflicts[.b]?.sorted() == ["buttonA", "buttonB"])
    #expect(conflicts.count == 1)
  }

  @Test func keyboardAndPadDoNotConflictAcrossDomains() {
    // Keyboard Z and pad buttonA both map to .b by default — intended.
    #expect(ButtonMapping.defaultMapping.conflicts().isEmpty)
  }

  @Test func roundTripsThroughJSONFile() throws {
    var mapping = ButtonMapping.defaultMapping
    mapping.pad["buttonA"] = .y

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mapping-\(UUID().uuidString).json")
    try ButtonMappingStore.save(mapping, to: url)
    let loaded = try ButtonMappingStore.load(from: url)
    #expect(loaded == mapping)
    #expect(loaded.pad["buttonA"] == .y)
  }

  @Test func loadMissingFileYieldsDefaults() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("absent-\(UUID().uuidString).json")
    let loaded = (try? ButtonMappingStore.load(from: url)) ?? .defaultMapping
    #expect(loaded == .defaultMapping)
  }
}
