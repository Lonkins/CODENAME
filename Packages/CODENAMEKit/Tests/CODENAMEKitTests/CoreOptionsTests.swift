import CLibretro
import Foundation
import Testing

@testable import CODENAMEKit

/// A NULL-terminated `retro_variable` array — the shape a core passes to
/// `SET_VARIABLES` — whose C strings stay alive as long as the block does.
private final class VariableBlock {
  let pointer: UnsafeMutablePointer<retro_variable>
  private var strings: [UnsafeMutablePointer<CChar>] = []
  private let count: Int

  init(_ pairs: [(String, String)]) {
    count = pairs.count + 1
    pointer = .allocate(capacity: count)
    pointer.initialize(repeating: retro_variable(), count: count)
    for (index, pair) in pairs.enumerated() {
      pointer[index].key = duplicate(pair.0)
      pointer[index].value = duplicate(pair.1)
    }
  }

  deinit {
    for string in strings { free(string) }
    pointer.deinitialize(count: count)
    pointer.deallocate()
  }

  private func duplicate(_ string: String) -> UnsafePointer<CChar>? {
    guard let copy = strdup(string) else { return nil }
    strings.append(copy)
    return UnsafePointer(copy)
  }
}

/// A `retro_core_options_v2` block: definitions terminated by a zeroed struct,
/// each carrying its values in the fixed-size C array the interface mandates.
private final class OptionsV2Block {
  let pointer: UnsafeMutablePointer<retro_core_options_v2>
  private let definitions: UnsafeMutablePointer<retro_core_option_v2_definition>
  private let definitionCount: Int
  private var strings: [UnsafeMutablePointer<CChar>] = []

  /// `values` are `(value, label)` pairs; a nil label is the "display the value
  /// itself" case the interface allows.
  init(_ declarations: [(key: String, desc: String, values: [(String, String?)], default: String?)])
  {
    definitionCount = declarations.count + 1
    definitions = .allocate(capacity: definitionCount)
    definitions.initialize(
      repeating: retro_core_option_v2_definition(), count: definitionCount)
    pointer = .allocate(capacity: 1)
    pointer.initialize(to: retro_core_options_v2())

    for (index, declaration) in declarations.enumerated() {
      definitions[index].key = duplicate(declaration.key)
      definitions[index].desc = duplicate(declaration.desc)
      definitions[index].default_value = declaration.default.flatMap { duplicate($0) }
      let slots = declaration.values.map {
        (duplicate($0.0), $0.1.flatMap { label in duplicate(label) })
      }
      withUnsafeMutablePointer(to: &definitions[index].values) { tuple in
        tuple.withMemoryRebound(
          to: retro_core_option_value.self, capacity: Int(RETRO_NUM_CORE_OPTION_VALUES_MAX)
        ) { array in
          for (slot, pair) in slots.enumerated() {
            array[slot].value = pair.0
            array[slot].label = pair.1
          }
        }
      }
    }
    pointer.pointee.definitions = definitions
  }

  deinit {
    for string in strings { free(string) }
    definitions.deinitialize(count: definitionCount)
    definitions.deallocate()
    pointer.deinitialize(count: 1)
    pointer.deallocate()
  }

  private func duplicate(_ string: String) -> UnsafePointer<CChar>? {
    guard let copy = strdup(string) else { return nil }
    strings.append(copy)
    return UnsafePointer(copy)
  }
}

/// A v1 `SET_CORE_OPTIONS` array: definitions terminated by a zeroed struct.
/// Same shape as v2 without the categorization fields.
private final class OptionsV1Block {
  let pointer: UnsafeMutablePointer<retro_core_option_definition>
  private let count: Int
  private var strings: [UnsafeMutablePointer<CChar>] = []

  init(_ declarations: [(key: String, desc: String, values: [(String, String?)], default: String?)])
  {
    count = declarations.count + 1
    pointer = .allocate(capacity: count)
    pointer.initialize(repeating: retro_core_option_definition(), count: count)
    for (index, declaration) in declarations.enumerated() {
      pointer[index].key = duplicate(declaration.key)
      pointer[index].desc = duplicate(declaration.desc)
      pointer[index].default_value = declaration.default.flatMap { duplicate($0) }
      let slots = declaration.values.map {
        (duplicate($0.0), $0.1.flatMap { label in duplicate(label) })
      }
      withUnsafeMutablePointer(to: &pointer[index].values) { tuple in
        tuple.withMemoryRebound(
          to: retro_core_option_value.self, capacity: Int(RETRO_NUM_CORE_OPTION_VALUES_MAX)
        ) { array in
          for (slot, pair) in slots.enumerated() {
            array[slot].value = pair.0
            array[slot].label = pair.1
          }
        }
      }
    }
  }

  deinit {
    for string in strings { free(string) }
    pointer.deinitialize(count: count)
    pointer.deallocate()
  }

  private func duplicate(_ string: String) -> UnsafePointer<CChar>? {
    guard let copy = strdup(string) else { return nil }
    strings.append(copy)
    return UnsafePointer(copy)
  }
}

@Suite struct CoreOptionsTests {

  // MARK: - v0 grammar (SET_VARIABLES)

  @Test func variablesParseTitleAndValues() {
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.count == 1)
    #expect(options.first?.key == "foo_speedhack")
    #expect(options.first?.title == "Speed hack")
    #expect(options.first?.values.map(\.value) == ["false", "true"])
  }

  @Test func variablesDefaultIsTheFirstListedValue() {
    let block = VariableBlock([("foo_displayscale", "Display scale factor; 1|2|3|4")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.first?.defaultValue == "1")
  }

  @Test func variablesToleratesMissingSpaceAfterSeparator() {
    let block = VariableBlock([("foo_scale", "Scale;1|2")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.first?.title == "Scale")
    #expect(options.first?.values.map(\.value) == ["1", "2"])
  }

  @Test func variablesSplitOnTheFirstSeparatorOnly() {
    // The grammar is explicit: everything before the *first* ';' is the title.
    let block = VariableBlock([("foo_x", "Title; a; b|c")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.first?.title == "Title")
    #expect(options.first?.values.map(\.value) == ["a; b", "c"])
  }

  @Test func variablesWithoutSeparatorAreIgnored() {
    let block = VariableBlock([("foo_broken", "no separator here")])
    #expect(CoreOptions.definitions(fromVariables: block.pointer).isEmpty)
  }

  @Test func variablesWithEmptyValueListAreIgnored() {
    let block = VariableBlock([("foo_empty", "Title; ")])
    #expect(CoreOptions.definitions(fromVariables: block.pointer).isEmpty)
  }

  @Test func variablesStopAtTheTerminator() {
    let block = VariableBlock([("a", "A; 1|2"), ("b", "B; 3|4")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.map(\.key) == ["a", "b"])
  }

  @Test func variablesCarryNoValueLabels() {
    let block = VariableBlock([("foo", "Foo; on|off")])
    let options = CoreOptions.definitions(fromVariables: block.pointer)
    #expect(options.first?.values.first?.label == nil)
    #expect(options.first?.values.first?.displayLabel == "on")
  }

  // MARK: - v2 definitions (SET_CORE_OPTIONS_V2)

  @Test func v2DefinitionsCarryLabelsAndDeclaredDefault() {
    let block = OptionsV2Block([
      (
        key: "psx_renderer", desc: "Renderer",
        values: [("software", "Software"), ("hardware", "Hardware")],
        default: "hardware"
      )
    ])
    let options = CoreOptions.definitions(fromV2: block.pointer)
    #expect(options.count == 1)
    #expect(options.first?.key == "psx_renderer")
    #expect(options.first?.title == "Renderer")
    #expect(options.first?.values.map(\.label) == ["Software", "Hardware"])
    #expect(options.first?.defaultValue == "hardware")
  }

  @Test func v2MissingDefaultFallsBackToTheFirstValue() {
    let block = OptionsV2Block([
      (key: "k", desc: "K", values: [("a", nil), ("b", nil)], default: nil)
    ])
    #expect(CoreOptions.definitions(fromV2: block.pointer).first?.defaultValue == "a")
  }

  @Test func v2DefaultOutsideTheValueListIgnoresTheOption() {
    // The interface says an option whose default is not among its values
    // "will be ignored" — honour that rather than inventing a fallback.
    let block = OptionsV2Block([
      (key: "k", desc: "K", values: [("a", nil), ("b", nil)], default: "zzz")
    ])
    #expect(CoreOptions.definitions(fromV2: block.pointer).isEmpty)
  }

  @Test func v2StopsAtTheZeroedDefinition() {
    let block = OptionsV2Block([
      (key: "one", desc: "One", values: [("a", nil)], default: "a"),
      (key: "two", desc: "Two", values: [("b", nil)], default: "b"),
    ])
    #expect(CoreOptions.definitions(fromV2: block.pointer).map(\.key) == ["one", "two"])
  }

  @Test func v2NilLabelDisplaysTheValue() {
    let block = OptionsV2Block([
      (key: "k", desc: "K", values: [("raw", nil)], default: "raw")
    ])
    #expect(
      CoreOptions.definitions(fromV2: block.pointer).first?.values.first?.displayLabel
        == "raw")
  }

  @Test func v2DefinitionWithNoValuesIsIgnored() {
    let block = OptionsV2Block([(key: "k", desc: "K", values: [], default: nil)])
    #expect(CoreOptions.definitions(fromV2: block.pointer).isEmpty)
  }

  @Test func v2EmptyDescriptionSurvivesAsAnEmptyTitle() {
    // The interface calls desc required, but a core that ships an empty one is
    // still usable — the option keeps working and simply displays no title.
    let block = OptionsV2Block([(key: "k", desc: "", values: [("a", nil)], default: "a")])
    let parsed = CoreOptions.definitions(fromV2: block.pointer)
    #expect(parsed.map(\.key) == ["k"])
    #expect(parsed.first?.title == "")
  }

  // MARK: - v1 definitions (SET_CORE_OPTIONS)

  @Test func v1DefinitionsCarryLabelsAndDeclaredDefault() {
    let block = OptionsV1Block([
      (
        key: "core_speed", desc: "Speed",
        values: [("normal", "Normal"), ("turbo", "Turbo")], default: "turbo"
      )
    ])
    let options = CoreOptions.definitions(fromV1: block.pointer)
    #expect(options.count == 1)
    #expect(options.first?.key == "core_speed")
    #expect(options.first?.title == "Speed")
    #expect(options.first?.values.map(\.label) == ["Normal", "Turbo"])
    #expect(options.first?.defaultValue == "turbo")
  }

  @Test func v1MissingDefaultFallsBackToTheFirstValue() {
    let block = OptionsV1Block([
      (key: "k", desc: "K", values: [("a", nil), ("b", nil)], default: nil)
    ])
    #expect(CoreOptions.definitions(fromV1: block.pointer).first?.defaultValue == "a")
  }

  @Test func v1DefaultOutsideTheValueListIgnoresTheOption() {
    let block = OptionsV1Block([
      (key: "k", desc: "K", values: [("a", nil)], default: "zzz")
    ])
    #expect(CoreOptions.definitions(fromV1: block.pointer).isEmpty)
  }

  @Test func v1StopsAtTheZeroedDefinition() {
    let block = OptionsV1Block([
      (key: "one", desc: "One", values: [("a", nil)], default: "a"),
      (key: "two", desc: "Two", values: [("b", nil)], default: "b"),
    ])
    #expect(CoreOptions.definitions(fromV1: block.pointer).map(\.key) == ["one", "two"])
  }

  // MARK: - Selection

  @Test func declaringSeedsEveryOptionWithItsDefault() {
    let options = CoreOptions()
    options.declare([
      CoreOption(
        key: "k", title: "K", values: [CoreOptionValue(value: "a"), CoreOptionValue(value: "b")],
        defaultValue: "b")
    ])
    #expect(options.value(for: "k") == "b")
  }

  @Test func unknownKeyHasNoValue() {
    let options = CoreOptions()
    #expect(options.value(for: "nothing") == nil)
  }

  @Test func settingAnOfferedValueSticks() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    #expect(options.setValue("b", for: "k"))
    #expect(options.value(for: "k") == "b")
  }

  @Test func settingAValueOutsideTheDefinitionIsRefused() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    #expect(!options.setValue("zzz", for: "k"))
    #expect(options.value(for: "k") == "a")
  }

  @Test func settingAnUnknownKeyIsRefused() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    #expect(!options.setValue("a", for: "other"))
  }

  @Test func redeclaringKeepsAChoiceThatIsStillOffered() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("b", for: "k")
    options.declare([twoValueOption])
    #expect(options.value(for: "k") == "b")
  }

  @Test func redeclaringRevertsAChoiceThatIsNoLongerOffered() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("b", for: "k")
    options.declare([
      CoreOption(
        key: "k", title: "K", values: [CoreOptionValue(value: "a")], defaultValue: "a")
    ])
    #expect(options.value(for: "k") == "a")
  }

  // MARK: - Update flag

  @Test func noUpdateIsReportedBeforeAnyChange() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    #expect(!options.takeUpdateFlag())
  }

  @Test func updateIsReportedOnceThenCleared() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("b", for: "k")
    #expect(options.takeUpdateFlag())
    #expect(!options.takeUpdateFlag())
  }

  @Test func refusedChangesRaiseNoUpdate() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("zzz", for: "k")
    #expect(!options.takeUpdateFlag())
  }

  @Test func settingTheSameValueRaisesNoUpdate() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("a", for: "k")
    #expect(!options.takeUpdateFlag())
  }

  @Test func redeclaringWithNoChangeRaisesNoUpdate() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("b", for: "k")
    _ = options.takeUpdateFlag()
    options.declare([twoValueOption])
    #expect(!options.takeUpdateFlag())
  }

  @Test func redeclaringThatDropsAChoiceRaisesUpdate() {
    // The core is still holding the value it last read; a silent revert would
    // leave it running on a setting the frontend no longer believes in.
    let options = CoreOptions()
    options.declare([twoValueOption])
    options.setValue("b", for: "k")
    _ = options.takeUpdateFlag()
    options.declare([
      CoreOption(key: "k", title: "K", values: [CoreOptionValue(value: "a")], defaultValue: "a")
    ])
    #expect(options.takeUpdateFlag())
  }

  @Test func firstDeclarationRaisesNoUpdate() {
    let options = CoreOptions()
    options.declare([twoValueOption])
    #expect(!options.takeUpdateFlag())
  }

  private var twoValueOption: CoreOption {
    CoreOption(
      key: "k", title: "K", values: [CoreOptionValue(value: "a"), CoreOptionValue(value: "b")],
      defaultValue: "a")
  }
}

@Suite struct CoreOptionsEnvironmentTests {
  private func makeHandler() -> EnvironmentHandler {
    EnvironmentHandler(
      systemDirectory: URL(fileURLWithPath: "/tmp/system"),
      saveDirectory: URL(fileURLWithPath: "/tmp/save"))
  }

  private func setVariables(_ handler: EnvironmentHandler, _ block: VariableBlock) -> Bool {
    handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_VARIABLES), data: block.pointer)
  }

  /// Performs a `GET_VARIABLE` the way a core does, returning the answer the
  /// frontend wrote back into the struct.
  private func getVariable(_ handler: EnvironmentHandler, key: String) -> (
    handled: Bool, value: String?
  ) {
    guard let keyCString = strdup(key) else { return (false, nil) }
    defer { free(keyCString) }
    var variable = retro_variable()
    variable.key = UnsafePointer(keyCString)
    let handled = withUnsafeMutablePointer(to: &variable) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_VARIABLE), data: $0)
    }
    return (handled, variable.value.map { String(cString: $0) })
  }

  @Test func coreOptionsVersionIsTwo() {
    let handler = makeHandler()
    var version: UInt32 = 0
    let handled = withUnsafeMutablePointer(to: &version) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION), data: $0)
    }
    #expect(handled)
    #expect(version == 2)
  }

  @Test func setVariablesRegistersTheDeclaredOptions() {
    let handler = makeHandler()
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    #expect(setVariables(handler, block))
    #expect(handler.options.definitions.map(\.key) == ["foo_speedhack"])
  }

  @Test func getVariableAnswersWithTheDefault() {
    let handler = makeHandler()
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    _ = setVariables(handler, block)
    let answer = getVariable(handler, key: "foo_speedhack")
    #expect(answer.handled)
    #expect(answer.value == "false")
  }

  @Test func getVariableAnswersWithTheUserChoice() {
    let handler = makeHandler()
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    _ = setVariables(handler, block)
    handler.options.setValue("true", for: "foo_speedhack")
    #expect(getVariable(handler, key: "foo_speedhack").value == "true")
  }

  @Test func getVariableIsAvailableEvenForAnUnknownKey() {
    // The interface requires `true` whenever the call is supported — a missing
    // key is signalled by leaving `value` NULL, not by refusing the call.
    let handler = makeHandler()
    let answer = getVariable(handler, key: "never_declared")
    #expect(answer.handled)
    #expect(answer.value == nil)
  }

  @Test func getVariableWithNullDataIsStillAvailable() {
    // Cores probe support this way; NULL must not be treated as a refusal.
    let handler = makeHandler()
    #expect(handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_VARIABLE), data: nil))
  }

  @Test func variableUpdateFollowsTheSelection() {
    let handler = makeHandler()
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    _ = setVariables(handler, block)

    var updated = true
    func queryUpdate() -> Bool {
      _ = withUnsafeMutablePointer(to: &updated) {
        handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE), data: $0)
      }
      return updated
    }

    #expect(!queryUpdate())
    handler.options.setValue("true", for: "foo_speedhack")
    #expect(queryUpdate())
    #expect(!queryUpdate())
  }

  @Test func setCoreOptionsRegistersOptionsAndReportsAvailable() {
    // A core told the options version is 2 may still speak version 1: the
    // shim that generation of cores vendored calls this and never falls back.
    let handler = makeHandler()
    let block = OptionsV1Block([
      (key: "core_speed", desc: "Speed", values: [("normal", nil), ("turbo", nil)], default: nil)
    ])
    let handled = handler.handle(
      command: UInt32(RETRO_ENVIRONMENT_SET_CORE_OPTIONS), data: block.pointer)
    #expect(handled)
    #expect(handler.options.definitions.map(\.key) == ["core_speed"])
    #expect(handler.options.value(for: "core_speed") == "normal")
  }

  @Test func setCoreOptionsIntlRegistersTheEnglishDefinitions() {
    let handler = makeHandler()
    let block = OptionsV1Block([
      (key: "core_speed", desc: "Speed", values: [("normal", nil)], default: nil)
    ])
    var intl = retro_core_options_intl()
    intl.us = block.pointer
    let handled = withUnsafeMutablePointer(to: &intl) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL), data: $0)
    }
    #expect(handled)
    #expect(handler.options.definitions.map(\.key) == ["core_speed"])
  }

  @Test func setCoreOptionsV2RegistersOptionsAndReportsNoCategorySupport() {
    // The return value advertises category support, not success — this
    // frontend has no category UI, so it answers false and still registers.
    let handler = makeHandler()
    let block = OptionsV2Block([
      (key: "psx_renderer", desc: "Renderer", values: [("software", "Software")], default: nil)
    ])
    let handled = handler.handle(
      command: UInt32(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2), data: block.pointer)
    #expect(!handled)
    #expect(handler.options.definitions.map(\.key) == ["psx_renderer"])
    #expect(handler.options.value(for: "psx_renderer") == "software")
  }

  @Test func setCoreOptionsV2IntlRegistersTheEnglishDefinitions() {
    // Cores built with translations call the _INTL variant; ignoring it would
    // leave every option unregistered for most modern cores.
    let handler = makeHandler()
    let block = OptionsV2Block([
      (key: "psx_renderer", desc: "Renderer", values: [("software", nil)], default: nil)
    ])
    var intl = retro_core_options_v2_intl()
    intl.us = block.pointer
    _ = withUnsafeMutablePointer(to: &intl) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL), data: $0)
    }
    #expect(handler.options.definitions.map(\.key) == ["psx_renderer"])
  }

  @Test func getVariableReflectsALaterChange() {
    // Reads the value twice around a change: the first read caches a C string,
    // and a cache that is not invalidated would hand the core the old one.
    let handler = makeHandler()
    let block = VariableBlock([("foo_speedhack", "Speed hack; false|true")])
    _ = setVariables(handler, block)
    #expect(getVariable(handler, key: "foo_speedhack").value == "false")
    handler.options.setValue("true", for: "foo_speedhack")
    #expect(getVariable(handler, key: "foo_speedhack").value == "true")
  }

  @Test func getVariableUpdateIsAvailable() {
    let handler = makeHandler()
    var updated = false
    let handled = withUnsafeMutablePointer(to: &updated) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE), data: $0)
    }
    #expect(handled)
  }

  @Test func nullDeclarationsAreAcceptedAndClearTheOptions() {
    // Every SET_* option command documents NULL data as legal.
    for command in [
      RETRO_ENVIRONMENT_SET_CORE_OPTIONS, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL,
      RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL,
    ] {
      let handler = makeHandler()
      let block = VariableBlock([("foo", "Foo; a|b")])
      _ = setVariables(handler, block)
      _ = handler.handle(command: UInt32(command), data: nil)
      #expect(handler.options.definitions.isEmpty)
    }
  }

  @Test func nullVariablesDeclarationLeavesOptionsAlone() {
    // SET_VARIABLES documents NULL as "still available", not as a reset.
    let handler = makeHandler()
    let block = VariableBlock([("foo", "Foo; a|b")])
    _ = setVariables(handler, block)
    #expect(handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_VARIABLES), data: nil))
    #expect(handler.options.definitions.map(\.key) == ["foo"])
  }

  @Test func everyOptionCommandIsHandledNotCounted() {
    let handler = makeHandler()
    var scratch: UInt32 = 0
    for command in [
      RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION, RETRO_ENVIRONMENT_SET_VARIABLES,
      RETRO_ENVIRONMENT_SET_CORE_OPTIONS, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL,
      RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL,
      RETRO_ENVIRONMENT_GET_VARIABLE, RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE,
    ] {
      _ = withUnsafeMutablePointer(to: &scratch) {
        handler.handle(command: UInt32(command), data: $0)
      }
    }
    #expect(handler.unknownCommandCount == 0)
  }

  @Test func optionCommandsAreNotCountedAsUnknown() {
    let handler = makeHandler()
    var version: UInt32 = 0
    _ = withUnsafeMutablePointer(to: &version) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION), data: $0)
    }
    _ = getVariable(handler, key: "anything")
    #expect(handler.unknownCommandCount == 0)
  }
}
