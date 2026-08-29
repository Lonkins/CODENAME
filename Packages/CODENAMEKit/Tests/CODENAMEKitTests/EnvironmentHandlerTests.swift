import CLibretro
import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct EnvironmentHandlerTests {
  private func makeHandler() -> EnvironmentHandler {
    EnvironmentHandler(
      systemDirectory: URL(fileURLWithPath: "/tmp/system"),
      saveDirectory: URL(fileURLWithPath: "/tmp/save")
    )
  }

  @Test func setPixelFormatAcceptsSupported() {
    let handler = makeHandler()
    var format = RETRO_PIXEL_FORMAT_RGB565
    let ok = withUnsafeMutablePointer(to: &format) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT), data: $0)
    }
    #expect(ok)
    #expect(handler.pixelFormat == .rgb565)
  }

  @Test func setPixelFormatRejectsUnknown() {
    let handler = makeHandler()
    var format = RETRO_PIXEL_FORMAT_UNKNOWN
    let ok = withUnsafeMutablePointer(to: &format) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT), data: $0)
    }
    #expect(!ok)
    #expect(handler.pixelFormat == nil)
  }

  @Test func canDupeWritesTrue() {
    let handler = makeHandler()
    var canDupe = false
    let ok = withUnsafeMutablePointer(to: &canDupe) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_CAN_DUPE), data: $0)
    }
    #expect(ok)
    #expect(canDupe)
  }

  @Test func hardwareRenderRefusedAndFlagged() {
    let handler = makeHandler()
    var callback = retro_hw_render_callback()
    let ok = withUnsafeMutablePointer(to: &callback) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_HW_RENDER), data: $0)
    }
    #expect(!ok)
    #expect(handler.hardwareRenderRequested)
  }

  @Test(arguments: [RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY])
  func directoriesVendStableCStrings(_ command: Int32) {
    let handler = makeHandler()
    var pointer: UnsafePointer<CChar>? = nil
    let ok = withUnsafeMutablePointer(to: &pointer) {
      handler.handle(command: UInt32(command), data: $0)
    }
    #expect(ok)
    let path = pointer.map { String(cString: $0) }
    let expected = command == RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY ? "/tmp/system" : "/tmp/save"
    #expect(path == expected)
  }

  @Test func unknownCommandRefusedAndCounted() {
    let handler = makeHandler()
    #expect(!handler.handle(command: 9999, data: nil))
    #expect(!handler.handle(command: 9999, data: nil))
    #expect(handler.unknownCommandCount == 2)
  }

  @Test func benignCommandsAccepted() {
    let handler = makeHandler()
    var level: UInt32 = 2
    let ok = withUnsafeMutablePointer(to: &level) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL), data: $0)
    }
    #expect(ok)
  }

  @Test func logInterfaceDeclined() {
    let handler = makeHandler()
    var iface = retro_log_callback()
    let ok = withUnsafeMutablePointer(to: &iface) {
      handler.handle(command: UInt32(RETRO_ENVIRONMENT_GET_LOG_INTERFACE), data: $0)
    }
    #expect(!ok)
  }
}
