import CLibretro
import Foundation

/// One running core. Deliberately non-Sendable: the owner confines it to a
/// single thread (the dedicated core thread in the app; see ADR 0003).
/// Copies every frame and audio batch out of core memory — no core pointer
/// survives a callback (ADR 0001 design constraint).
public final class CoreSession {
  public enum SessionError: Error, Equatable {
    case load(LoadError)
    case hardwareRenderUnsupported
    case gameRejected
    case alreadyActive
    case serializationFailed
  }

  public struct VideoFrame: Equatable {
    public let width: Int
    public let height: Int
    public let pitch: Int
    public let pixelFormat: LibretroPixelFormat
    public let bytes: [UInt8]
  }

  public private(set) var avInfo: CoreAVInfo?
  public private(set) var latestFrame: VideoFrame?
  public private(set) var audioSamples: [Int16] = []
  public let inputState: InputState

  private let library: CoreLibrary
  private let environment: EnvironmentHandler
  private var isActive = true

  // libretro callbacks are context-free C function pointers, so the running
  // session lives in one static slot. Safe because sessions are exclusive
  // (alreadyActive guard) and all core calls happen on the owning thread.
  private nonisolated(unsafe) static var current: CoreSession?

  public init(
    coreURL: URL, policy: CoreTrustPolicy, environment: EnvironmentHandler,
    inputState: InputState = InputState()
  ) throws(SessionError) {
    guard Self.current == nil else { throw .alreadyActive }
    do {
      library = try CoreLibrary(url: coreURL, policy: policy)
    } catch {
      throw .load(error)
    }
    self.environment = environment
    self.inputState = inputState
    Self.current = self

    // Spec order: environment callback first, then the rest, then retro_init.
    library.symbols.setEnvironment { command, data in
      CoreSession.current?.environment.handle(command: command, data: data) ?? false
    }
    library.symbols.setVideoRefresh { data, width, height, pitch in
      CoreSession.current?.captureVideo(data: data, width: width, height: height, pitch: pitch)
    }
    library.symbols.setAudioSample { left, right in
      CoreSession.current?.audioSamples.append(contentsOf: [left, right])
    }
    library.symbols.setAudioSampleBatch { data, frames in
      CoreSession.current?.captureAudio(data: data, frames: frames) ?? 0
    }
    library.symbols.setInputPoll {}
    library.symbols.setInputState { port, device, _, id in
      guard port == 0, device == UInt32(RETRO_DEVICE_JOYPAD) else { return 0 }
      return CoreSession.current?.inputState.value(forDeviceID: id) ?? 0
    }
    library.symbols.initCore()
  }

  deinit {
    shutdown()
  }

  public func loadGame(path: String?) throws(SessionError) {
    var loaded = false
    if let path {
      var info = retro_system_info()
      library.symbols.getSystemInfo(&info)
      if info.need_fullpath {
        // The core streams from disk itself (disc images, playlists) — the
        // host must NOT slurp a possibly multi-hundred-MB file (ADR 0007).
        loaded = path.withCString { cPath in
          var game = retro_game_info()
          game.path = cPath
          return library.symbols.loadGame(&game)
        }
      } else {
        // The core reads (and must copy) the data buffer, per the libretro
        // contract; the path rides along for cores that peek at it.
        guard let contents = FileManager.default.contents(atPath: path) else {
          throw .gameRejected
        }
        loaded = path.withCString { cPath in
          contents.withUnsafeBytes { raw in
            var game = retro_game_info()
            game.path = cPath
            game.data = raw.baseAddress
            game.size = contents.count
            return library.symbols.loadGame(&game)
          }
        }
      }
    } else {
      loaded = library.symbols.loadGame(nil)
    }
    guard loaded else { throw .gameRejected }

    if environment.hardwareRenderRequested {
      library.symbols.unloadGame()
      throw .hardwareRenderUnsupported
    }

    var info = retro_system_av_info()
    library.symbols.getSystemAVInfo(&info)
    avInfo = CoreAVInfo(info)
  }

  public func run(frames: Int) {
    for _ in 0..<frames {
      library.symbols.run()
    }
  }

  /// Copy of the core's save RAM, or nil when the core exposes none.
  /// Snapshot semantics per ADR 0001 — the live pointer never escapes.
  public func saveRAMSnapshot() -> [UInt8]? {
    let size = library.symbols.getMemorySize(UInt32(RETRO_MEMORY_SAVE_RAM))
    guard size > 0, let data = library.symbols.getMemoryData(UInt32(RETRO_MEMORY_SAVE_RAM)) else {
      return nil
    }
    return [UInt8](UnsafeRawBufferPointer(start: data, count: size))
  }

  /// Copies persisted save RAM into the core; false on size mismatch or none.
  public func restoreSaveRAM(_ bytes: [UInt8]) -> Bool {
    let size = library.symbols.getMemorySize(UInt32(RETRO_MEMORY_SAVE_RAM))
    guard size == bytes.count, size > 0,
      let data = library.symbols.getMemoryData(UInt32(RETRO_MEMORY_SAVE_RAM))
    else { return false }
    bytes.withUnsafeBytes { source in
      guard let base = source.baseAddress else { return }
      data.copyMemory(from: base, byteCount: size)
    }
    return true
  }

  /// Returns accumulated samples and clears the buffer (bounds session memory;
  /// the caller feeds them into the audio ring).
  public func drainAudioSamples() -> [Int16] {
    let drained = audioSamples
    audioSamples.removeAll(keepingCapacity: true)
    return drained
  }

  public func serialize() throws(SessionError) -> [UInt8] {
    let size = library.symbols.serializeSize()
    guard size > 0 else { throw .serializationFailed }
    var buffer = [UInt8](repeating: 0, count: size)
    let ok = buffer.withUnsafeMutableBytes { library.symbols.serialize($0.baseAddress, size) }
    guard ok else { throw .serializationFailed }
    return buffer
  }

  public func unserialize(_ data: [UInt8]) throws(SessionError) {
    let ok = data.withUnsafeBytes { library.symbols.unserialize($0.baseAddress, data.count) }
    guard ok else { throw .serializationFailed }
  }

  public func shutdown() {
    guard isActive else { return }
    isActive = false
    library.symbols.unloadGame()
    library.symbols.deinitCore()
    if Self.current === self { Self.current = nil }
  }

  private func captureVideo(data: UnsafeRawPointer?, width: UInt32, height: UInt32, pitch: Int) {
    // nil data = "duplicate frame" (we advertise GET_CAN_DUPE); keep the last one.
    guard let data else { return }
    latestFrame = VideoFrame(
      width: Int(width),
      height: Int(height),
      pitch: pitch,
      // Spec default when a core never sets a format.
      pixelFormat: environment.pixelFormat ?? .zeroRGB1555,
      bytes: [UInt8](UnsafeRawBufferPointer(start: data, count: pitch * Int(height)))
    )
  }

  private func captureAudio(data: UnsafePointer<Int16>?, frames: Int) -> Int {
    guard let data else { return 0 }
    audioSamples.append(contentsOf: UnsafeBufferPointer(start: data, count: frames * 2))
    return frames
  }
}
