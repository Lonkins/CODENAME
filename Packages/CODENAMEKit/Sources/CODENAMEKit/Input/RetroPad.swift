import CLibretro
import Foundation
import Synchronization

/// RetroPad buttons, raw-valued for JSON mapping, with libretro device IDs.
public enum RetroPadButton: String, Codable, CaseIterable, Sendable {
  case b, y, select, start, up, down, left, right, a, x, l, r, l2, r2, l3, r3

  public var deviceID: UInt32 {
    switch self {
    case .b: UInt32(RETRO_DEVICE_ID_JOYPAD_B)
    case .y: UInt32(RETRO_DEVICE_ID_JOYPAD_Y)
    case .select: UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT)
    case .start: UInt32(RETRO_DEVICE_ID_JOYPAD_START)
    case .up: UInt32(RETRO_DEVICE_ID_JOYPAD_UP)
    case .down: UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN)
    case .left: UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT)
    case .right: UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT)
    case .a: UInt32(RETRO_DEVICE_ID_JOYPAD_A)
    case .x: UInt32(RETRO_DEVICE_ID_JOYPAD_X)
    case .l: UInt32(RETRO_DEVICE_ID_JOYPAD_L)
    case .r: UInt32(RETRO_DEVICE_ID_JOYPAD_R)
    case .l2: UInt32(RETRO_DEVICE_ID_JOYPAD_L2)
    case .r2: UInt32(RETRO_DEVICE_ID_JOYPAD_R2)
    case .l3: UInt32(RETRO_DEVICE_ID_JOYPAD_L3)
    case .r3: UInt32(RETRO_DEVICE_ID_JOYPAD_R3)
    }
  }
}

/// Pressed-button state shared between input sources (main thread) and the
/// core thread's input callback: one atomic bitmask keyed by device ID.
public final class InputState: Sendable {
  private let bits = Atomic<UInt32>(0)

  public init() {}

  public func set(_ button: RetroPadButton, pressed: Bool) {
    let mask = UInt32(1) << button.deviceID
    if pressed {
      bits.bitwiseOr(mask, ordering: .relaxed)
    } else {
      bits.bitwiseAnd(~mask, ordering: .relaxed)
    }
  }

  public func value(forDeviceID id: UInt32) -> Int16 {
    guard id < 32 else { return 0 }
    return (bits.load(ordering: .relaxed) >> id) & 1 == 1 ? 1 : 0
  }
}
