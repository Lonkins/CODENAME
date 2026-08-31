import CLibretro
import Foundation

/// One selectable value for a core option. `label` is the display text the v2
/// interface lets a core supply; the older variables grammar has none, and the
/// raw value is shown instead.
public struct CoreOptionValue: Equatable, Sendable {
  public let value: String
  public let label: String?

  public init(value: String, label: String? = nil) {
    self.value = value
    self.label = label
  }

  public var displayLabel: String { label ?? value }
}

/// A core option: the key the core queries, its human-readable title, the
/// values it accepts, and the value that applies until the user picks another.
public struct CoreOption: Equatable, Sendable {
  public let key: String
  public let title: String
  public let values: [CoreOptionValue]
  public let defaultValue: String

  public init(key: String, title: String, values: [CoreOptionValue], defaultValue: String) {
    self.key = key
    self.title = title
    self.values = values
    self.defaultValue = defaultValue
  }
}

/// The frontend half of the libretro core-options contract: it holds what the
/// core declared, what the user chose, and the C strings the core reads back
/// through `GET_VARIABLE`.
///
/// Not thread-safe — it belongs to the core thread that owns the session, the
/// same ownership `EnvironmentHandler` already has.
public final class CoreOptions {
  public private(set) var definitions: [CoreOption] = []

  private var selected: [String: String] = [:]
  private var buffers: [String: UnsafeMutablePointer<CChar>] = [:]
  /// Buffers a core may still hold a pointer to. The interface gives no moment
  /// at which a handed-out string is provably dead, so nothing is freed until
  /// the session ends; the count is bounded by user option changes.
  private var retired: [UnsafeMutablePointer<CChar>] = []

  private var changedSinceQuery = false

  public init() {}

  deinit {
    for buffer in buffers.values { free(buffer) }
    for buffer in retired { free(buffer) }
  }

  /// Replaces the declared options. Cores may re-declare mid-session; a value
  /// the user already chose survives as long as it is still offered.
  public func declare(_ options: [CoreOption]) {
    definitions = options
    var kept: [String: String] = [:]
    for option in options {
      if let existing = selected[option.key],
        option.values.contains(where: { $0.value == existing })
      {
        kept[option.key] = existing
      } else {
        kept[option.key] = option.defaultValue
      }
    }
    selected = kept
    retired.append(contentsOf: buffers.values)
    buffers.removeAll()
  }

  public func value(for key: String) -> String? { selected[key] }

  /// Records the user's choice. Refuses keys the core never declared and values
  /// it does not offer, so a stale stored setting can never reach a core.
  @discardableResult
  public func setValue(_ value: String, for key: String) -> Bool {
    guard let option = definitions.first(where: { $0.key == key }),
      option.values.contains(where: { $0.value == value })
    else { return false }
    guard selected[key] != value else { return true }
    selected[key] = value
    if let stale = buffers.removeValue(forKey: key) { retired.append(stale) }
    changedSinceQuery = true
    return true
  }

  /// Answers `GET_VARIABLE_UPDATE`: true once after any change, then false
  /// until the next one.
  func takeUpdateFlag() -> Bool {
    defer { changedSinceQuery = false }
    return changedSinceQuery
  }

  /// The value as a C string the core can hold, or nil for an undeclared key —
  /// which the interface signals by leaving `retro_variable.value` NULL.
  func cString(for key: String) -> UnsafePointer<CChar>? {
    if let existing = buffers[key] { return UnsafePointer(existing) }
    guard let value = selected[key], let created = strdup(value) else { return nil }
    buffers[key] = created
    return UnsafePointer(created)
  }
}

// MARK: - Parsing the two declaration interfaces

extension CoreOptions {
  /// `SET_VARIABLES`: an array of `{ key, "Title; a|b|c" }` terminated by a
  /// pair of NULLs. The first listed value is the default.
  static func definitions(fromVariables data: UnsafePointer<retro_variable>) -> [CoreOption] {
    var result: [CoreOption] = []
    var index = 0
    while let key = data[index].key, let spec = data[index].value {
      if let option = option(key: String(cString: key), spec: String(cString: spec)) {
        result.append(option)
      }
      index += 1
    }
    return result
  }

  /// The grammar is exact: everything before the *first* ';' is the title, the
  /// rest is a '|'-delimited value list.
  private static func option(key: String, spec: String) -> CoreOption? {
    guard !key.isEmpty, let separator = spec.firstIndex(of: ";") else { return nil }
    let title = spec[..<separator].trimmingCharacters(in: .whitespaces)
    let values = spec[spec.index(after: separator)...]
      .split(separator: "|")
      .map { CoreOptionValue(value: $0.trimmingCharacters(in: .whitespaces)) }
      .filter { !$0.value.isEmpty }
    guard let first = values.first else { return nil }
    return CoreOption(key: key, title: title, values: values, defaultValue: first.value)
  }

  /// `SET_CORE_OPTIONS_V2`: definitions terminated by a zeroed struct, each
  /// carrying its values in a fixed-size array terminated the same way.
  static func definitions(fromV2 data: UnsafePointer<retro_core_options_v2>) -> [CoreOption] {
    guard let definitions = data.pointee.definitions else { return [] }
    var result: [CoreOption] = []
    var index = 0
    while definitions[index].key != nil {
      if let option = option(fromV2: definitions[index]) { result.append(option) }
      index += 1
    }
    return result
  }

  private static func option(fromV2 definition: retro_core_option_v2_definition) -> CoreOption? {
    guard let key = definition.key, let desc = definition.desc else { return nil }
    let values = withUnsafePointer(to: definition.values) { tuple in
      tuple.withMemoryRebound(
        to: retro_core_option_value.self, capacity: Int(RETRO_NUM_CORE_OPTION_VALUES_MAX)
      ) { array -> [CoreOptionValue] in
        var values: [CoreOptionValue] = []
        var index = 0
        while index < Int(RETRO_NUM_CORE_OPTION_VALUES_MAX), let value = array[index].value {
          values.append(
            CoreOptionValue(
              value: String(cString: value),
              label: array[index].label.map { String(cString: $0) }))
          index += 1
        }
        return values
      }
    }
    guard let first = values.first else { return nil }

    // A declared default outside the value list means the option is ignored;
    // no default at all falls back to the first value.
    guard let declared = definition.default_value else {
      return CoreOption(
        key: String(cString: key), title: String(cString: desc), values: values,
        defaultValue: first.value)
    }
    let defaultValue = String(cString: declared)
    guard values.contains(where: { $0.value == defaultValue }) else { return nil }
    return CoreOption(
      key: String(cString: key), title: String(cString: desc), values: values,
      defaultValue: defaultValue)
  }
}
