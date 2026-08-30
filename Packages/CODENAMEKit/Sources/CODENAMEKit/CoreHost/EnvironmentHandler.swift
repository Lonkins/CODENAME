import CLibretro
import Foundation

/// Allowlisted handling of `retro_environment_t` commands (ADR 0001: portability-
/// classified; anything unknown is refused and counted, never guessed at).
/// Reference type: it owns C string buffers whose pointers cores retain.
public final class EnvironmentHandler {
  public private(set) var pixelFormat: LibretroPixelFormat?
  public private(set) var hardwareRenderRequested = false
  public private(set) var unknownCommandCount = 0

  private let systemDirectoryCString: UnsafeMutablePointer<CChar>
  private let saveDirectoryCString: UnsafeMutablePointer<CChar>
  private let jitCapable: Bool

  /// `jitCapable` is true only in the helper process (ADR 0006 decision 5:
  /// the JIT entitlement — and therefore the JIT answer — never belongs to
  /// the main app).
  public init(systemDirectory: URL, saveDirectory: URL, jitCapable: Bool = false) {
    systemDirectoryCString = strdup(systemDirectory.path)
    saveDirectoryCString = strdup(saveDirectory.path)
    self.jitCapable = jitCapable
  }

  deinit {
    free(systemDirectoryCString)
    free(saveDirectoryCString)
  }

  public func handle(command: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
    switch Int32(bitPattern: command) {
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
      data?.assumingMemoryBound(to: Bool.self).pointee = true
      return true

    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
      return true

    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
      data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        .pointee = UnsafePointer(systemDirectoryCString)
      return true

    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
      data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        .pointee = UnsafePointer(saveDirectoryCString)
      return true

    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
      guard let data,
        let format = LibretroPixelFormat(
          data.assumingMemoryBound(to: retro_pixel_format.self).pointee)
      else { return false }
      pixelFormat = format
      return true

    case RETRO_ENVIRONMENT_SET_HW_RENDER:
      // Phase 1 is software-rendered only; the session turns this flag into
      // a precise load failure (north star; hardware render is Phase 4).
      hardwareRenderRequested = true
      return false

    case RETRO_ENVIRONMENT_SET_VARIABLES:
      // ponytail: variables accepted but unstored; core options UI comes with the library UI phase.
      return true

    case RETRO_ENVIRONMENT_GET_VARIABLE, RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
      return false

    case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
      guard jitCapable else { return false }
      data?.assumingMemoryBound(to: Bool.self).pointee = true
      return true

    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
      // retro_log_printf_t is variadic C — unimplementable from Swift; cores fall back to stderr.
      return false

    default:
      unknownCommandCount += 1
      return false
    }
  }
}
