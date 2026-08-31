/// Pure pacing math from ADR 0003. The session layer applies these decisions;
/// nothing here touches Metal, audio, or threads.
public enum FramePacer {
  public enum Mode: Equatable, Sendable {
    case videoMaster(vblanksPerFrame: Int)
    case audioMaster
  }

  private static let maxVblanksPerFrame = 8

  /// Video-master when some integer vblank divisor brings the display within
  /// `maxMismatch` relative error of the core rate; otherwise audio-master.
  public static func mode(
    coreFPS: Double, displayRefresh: Double, maxMismatch: Double = 0.05
  ) -> Mode {
    guard coreFPS > 0, displayRefresh > 0 else { return .audioMaster }
    var best = (vblanks: 1, error: Double.infinity)
    for vblanks in 1...maxVblanksPerFrame {
      let effective = displayRefresh / Double(vblanks)
      let error = abs(effective - coreFPS) / coreFPS
      if error < best.error {
        best = (vblanks, error)
      }
    }
    return best.error <= maxMismatch ? .videoMaster(vblanksPerFrame: best.vblanks) : .audioMaster
  }

  /// The per-vblank decision both display loops run on. Video-master runs
  /// one frame every N vblanks; the audio-master fallback runs the core at
  /// its own rate against the display's clock, which is what keeps 50Hz
  /// content at 50Hz on a 60Hz panel instead of 20% fast.
  public struct FrameClock: Equatable, Sendable {
    /// A hitch must not turn into an unbounded burst of core frames.
    public static let maxCatchUp = 4

    public let framesPerVblank: Double
    private var credit = 0.0

    public init(mode: Mode, coreFPS: Double, displayRefresh: Double) {
      switch mode {
      case .videoMaster(let vblanksPerFrame):
        framesPerVblank = 1 / Double(max(vblanksPerFrame, 1))
      case .audioMaster:
        framesPerVblank = displayRefresh > 0 ? coreFPS / displayRefresh : 1
      }
    }

    /// How many core frames this vblank owes. Fractional rates accumulate,
    /// so the long-run average is the core's own rate.
    public mutating func framesDue() -> Int {
      credit += framesPerVblank
      let due = min(Int(credit.rounded(.down)), Self.maxCatchUp)
      credit -= Double(due)
      return due
    }
  }

  /// Dynamic rate control: nudge the resample ratio linearly with ring
  /// occupancy, clamped to ±maxDeviation. Occupancy 0.5 is the setpoint.
  public static func resampleRatio(
    base: Double, occupancy: Double, maxDeviation: Double = 0.005
  ) -> Double {
    let clamped = min(max(occupancy, 0), 1)
    return base * (1 + maxDeviation * (2 * clamped - 1))
  }
}
