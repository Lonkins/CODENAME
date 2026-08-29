import CLibretro
import Foundation

/// The complete set of libretro entry points a core must export.
public struct CoreSymbols {
  public let apiVersion: @convention(c) () -> UInt32
  public let initCore: @convention(c) () -> Void
  public let deinitCore: @convention(c) () -> Void
  public let getSystemInfo: @convention(c) (UnsafeMutablePointer<retro_system_info>?) -> Void
  public let getSystemAVInfo: @convention(c) (UnsafeMutablePointer<retro_system_av_info>?) -> Void
  public let setEnvironment: @convention(c) (retro_environment_t?) -> Void
  public let setVideoRefresh: @convention(c) (retro_video_refresh_t?) -> Void
  public let setAudioSample: @convention(c) (retro_audio_sample_t?) -> Void
  public let setAudioSampleBatch: @convention(c) (retro_audio_sample_batch_t?) -> Void
  public let setInputPoll: @convention(c) (retro_input_poll_t?) -> Void
  public let setInputState: @convention(c) (retro_input_state_t?) -> Void
  public let loadGame: @convention(c) (UnsafePointer<retro_game_info>?) -> Bool
  public let unloadGame: @convention(c) () -> Void
  public let run: @convention(c) () -> Void
  public let serializeSize: @convention(c) () -> Int
  public let serialize: @convention(c) (UnsafeMutableRawPointer?, Int) -> Bool
  public let unserialize: @convention(c) (UnsafeRawPointer?, Int) -> Bool
  public let getMemoryData: @convention(c) (UInt32) -> UnsafeMutableRawPointer?
  public let getMemorySize: @convention(c) (UInt32) -> Int
}

/// A verified, opened core dylib. Verification order is fixed: trust policy,
/// then `dlopen` (kernel library validation), then symbol and version checks.
public final class CoreLibrary {
  public let symbols: CoreSymbols
  private let handle: UnsafeMutableRawPointer

  public init(url: URL, policy: CoreTrustPolicy) throws(LoadError) {
    try policy.validate(url)

    guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
      let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen failure"
      throw .libraryOpenFailed(reason)
    }

    do {
      func resolve<T>(_ name: String, as type: T.Type) throws(LoadError) -> T {
        guard let symbol = dlsym(handle, name) else { throw .missingSymbol(name) }
        return unsafeBitCast(symbol, to: T.self)
      }

      let symbols = CoreSymbols(
        apiVersion: try resolve("retro_api_version", as: (@convention(c) () -> UInt32).self),
        initCore: try resolve("retro_init", as: (@convention(c) () -> Void).self),
        deinitCore: try resolve("retro_deinit", as: (@convention(c) () -> Void).self),
        getSystemInfo: try resolve(
          "retro_get_system_info",
          as: (@convention(c) (UnsafeMutablePointer<retro_system_info>?) -> Void).self),
        getSystemAVInfo: try resolve(
          "retro_get_system_av_info",
          as: (@convention(c) (UnsafeMutablePointer<retro_system_av_info>?) -> Void).self),
        setEnvironment: try resolve(
          "retro_set_environment", as: (@convention(c) (retro_environment_t?) -> Void).self),
        setVideoRefresh: try resolve(
          "retro_set_video_refresh", as: (@convention(c) (retro_video_refresh_t?) -> Void).self),
        setAudioSample: try resolve(
          "retro_set_audio_sample", as: (@convention(c) (retro_audio_sample_t?) -> Void).self),
        setAudioSampleBatch: try resolve(
          "retro_set_audio_sample_batch",
          as: (@convention(c) (retro_audio_sample_batch_t?) -> Void).self),
        setInputPoll: try resolve(
          "retro_set_input_poll", as: (@convention(c) (retro_input_poll_t?) -> Void).self),
        setInputState: try resolve(
          "retro_set_input_state", as: (@convention(c) (retro_input_state_t?) -> Void).self),
        loadGame: try resolve(
          "retro_load_game", as: (@convention(c) (UnsafePointer<retro_game_info>?) -> Bool).self),
        unloadGame: try resolve("retro_unload_game", as: (@convention(c) () -> Void).self),
        run: try resolve("retro_run", as: (@convention(c) () -> Void).self),
        serializeSize: try resolve("retro_serialize_size", as: (@convention(c) () -> Int).self),
        serialize: try resolve(
          "retro_serialize", as: (@convention(c) (UnsafeMutableRawPointer?, Int) -> Bool).self),
        unserialize: try resolve(
          "retro_unserialize", as: (@convention(c) (UnsafeRawPointer?, Int) -> Bool).self),
        getMemoryData: try resolve(
          "retro_get_memory_data", as: (@convention(c) (UInt32) -> UnsafeMutableRawPointer?).self),
        getMemorySize: try resolve(
          "retro_get_memory_size", as: (@convention(c) (UInt32) -> Int).self)
      )

      let version = symbols.apiVersion()
      guard version == UInt32(RETRO_API_VERSION) else {
        throw LoadError.unsupportedAPIVersion(version)
      }

      self.handle = handle
      self.symbols = symbols
    } catch let error as LoadError {
      dlclose(handle)
      throw error
    } catch {
      dlclose(handle)
      throw .libraryOpenFailed("\(error)")
    }
  }

  deinit {
    dlclose(handle)
  }
}
