import Synchronization

/// Display options resolved per session: per-game override beats global.
public struct DisplaySettings: Codable, Equatable, Sendable {
  public var integerScale: Bool

  public init(integerScale: Bool = true) {
    self.integerScale = integerScale
  }

  public static func resolve(global: DisplaySettings, override: DisplaySettings?)
    -> DisplaySettings
  {
    override ?? global
  }
}

/// Live view of the session's display settings: written by the settings UI on
/// the main thread, read by the core thread each frame — no UserDefaults in
/// the render path.
public final class LiveDisplaySettings: Sendable {
  private let integerScaleBit: Atomic<Bool>

  public init(_ settings: DisplaySettings) {
    integerScaleBit = Atomic(settings.integerScale)
  }

  public var integerScale: Bool {
    get { integerScaleBit.load(ordering: .relaxed) }
    set { integerScaleBit.store(newValue, ordering: .relaxed) }
  }
}
