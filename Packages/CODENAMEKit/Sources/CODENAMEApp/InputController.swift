import CODENAMEKit
import GameController

/// Bridges GameController devices (extended gamepads + keyboard) into the
/// shared InputState. Runs on the main thread; the core thread reads the
/// atomic state through the session's input callback.
@MainActor
final class InputController: NSObject {
  private let inputState: InputState
  private let mapping: ButtonMapping

  init(inputState: InputState, mapping: ButtonMapping = .defaultMapping) {
    self.inputState = inputState
    self.mapping = mapping
    super.init()
  }

  func start() {
    // GameController posts these on the main thread; selector observers avoid
    // Sendable friction with the payload objects.
    NotificationCenter.default.addObserver(
      self, selector: #selector(controllerConnected(_:)),
      name: .GCControllerDidConnect, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardConnected(_:)),
      name: .GCKeyboardDidConnect, object: nil)
    GCController.controllers().forEach(wire)
    if let keyboard = GCKeyboard.coalesced {
      wire(keyboard)
    }
  }

  @objc private func controllerConnected(_ notification: Notification) {
    guard let controller = notification.object as? GCController else { return }
    wire(controller)
  }

  @objc private func keyboardConnected(_ notification: Notification) {
    guard let keyboard = notification.object as? GCKeyboard else { return }
    wire(keyboard)
  }

  private func wire(_ controller: GCController) {
    guard let pad = controller.extendedGamepad else { return }
    let buttons: [(String, GCControllerButtonInput?)] = [
      ("buttonA", pad.buttonA), ("buttonB", pad.buttonB),
      ("buttonX", pad.buttonX), ("buttonY", pad.buttonY),
      ("dpadUp", pad.dpad.up), ("dpadDown", pad.dpad.down),
      ("dpadLeft", pad.dpad.left), ("dpadRight", pad.dpad.right),
      ("leftShoulder", pad.leftShoulder), ("rightShoulder", pad.rightShoulder),
      ("leftTrigger", pad.leftTrigger), ("rightTrigger", pad.rightTrigger),
      ("leftThumbstickButton", pad.leftThumbstickButton),
      ("rightThumbstickButton", pad.rightThumbstickButton),
      ("menu", pad.buttonMenu), ("options", pad.buttonOptions),
    ]
    for (name, input) in buttons {
      guard let input, let button = mapping.button(forPad: name) else { continue }
      let state = inputState
      input.pressedChangedHandler = { _, _, pressed in
        state.set(button, pressed: pressed)
      }
    }
  }

  private func wire(_ keyboard: GCKeyboard) {
    guard let keyboardInput = keyboard.keyboardInput else { return }
    let state = inputState
    let mapping = mapping
    keyboardInput.keyChangedHandler = { _, _, keyCode, pressed in
      guard let button = mapping.button(forKeyCode: Int(keyCode.rawValue)) else { return }
      state.set(button, pressed: pressed)
    }
  }
}
