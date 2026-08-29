import Foundation

/// Physical control → RetroPad button, persisted as JSON per core.
/// Pad keys are GameController element names; keyboard keys are GCKeyCode
/// raw values as strings.
public struct ButtonMapping: Codable, Equatable, Sendable {
  public var pad: [String: RetroPadButton]
  public var keyboard: [String: RetroPadButton]

  public func button(forPad name: String) -> RetroPadButton? {
    pad[name]
  }

  public func button(forKeyCode raw: Int) -> RetroPadButton? {
    keyboard[String(raw)]
  }

  /// Buttons assigned to more than one physical control *within a domain*
  /// (pad or keyboard); cross-domain duplication is intentional.
  public func conflicts() -> [RetroPadButton: [String]] {
    var result: [RetroPadButton: [String]] = [:]
    for domain in [pad, keyboard] {
      var byButton: [RetroPadButton: [String]] = [:]
      for (control, button) in domain {
        byButton[button, default: []].append(control)
      }
      for (button, controls) in byButton where controls.count > 1 {
        result[button, default: []].append(contentsOf: controls)
      }
    }
    return result
  }

  /// Nintendo-style pad layout; keyboard uses arrows + Z/X/A/S.
  public static let defaultMapping = ButtonMapping(
    pad: [
      "buttonA": .b, "buttonB": .a, "buttonX": .y, "buttonY": .x,
      "dpadUp": .up, "dpadDown": .down, "dpadLeft": .left, "dpadRight": .right,
      "leftShoulder": .l, "rightShoulder": .r,
      "leftTrigger": .l2, "rightTrigger": .r2,
      "leftThumbstickButton": .l3, "rightThumbstickButton": .r3,
      "menu": .start, "options": .select,
    ],
    keyboard: [
      // GCKeyCode raw values: arrows 79-82, Z=29, X=27, A=4, S=22,
      // Q=20, W=26, Return=40, RightShift=229.
      "82": .up, "81": .down, "80": .left, "79": .right,
      "29": .b, "27": .a, "4": .y, "22": .x,
      "20": .l, "26": .r, "40": .start, "229": .select,
    ])
}

public enum ButtonMappingStore {
  public static func save(_ mapping: ButtonMapping, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(mapping).write(to: url, options: .atomic)
  }

  public static func load(from url: URL) throws -> ButtonMapping {
    try JSONDecoder().decode(ButtonMapping.self, from: Data(contentsOf: url))
  }
}
