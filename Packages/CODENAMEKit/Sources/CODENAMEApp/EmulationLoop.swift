import CODENAMEKit
import QuartzCore

/// What a game window needs from a running session, whichever process hosts
/// the core: in-process (CoreDisplayLoop) or the XPC helper
/// (HelperDisplayLoop, ADR 0007).
protocol EmulationLoop: AnyObject {
  var inputState: InputState { get }
  var displaySettings: LiveDisplaySettings { get }
  func start()
  func stop()
  func requestSaveState(slot: Int)
  func requestLoadState(slot: Int)
}

extension CoreDisplayLoop: EmulationLoop {}
extension HelperDisplayLoop: EmulationLoop {}
