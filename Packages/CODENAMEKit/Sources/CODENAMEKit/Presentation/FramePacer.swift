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

  /// Dynamic rate control: nudge the resample ratio linearly with ring
  /// occupancy, clamped to ±maxDeviation. Occupancy 0.5 is the setpoint.
  public static func resampleRatio(
    base: Double, occupancy: Double, maxDeviation: Double = 0.005
  ) -> Double {
    let clamped = min(max(occupancy, 0), 1)
    return base * (1 + maxDeviation * (2 * clamped - 1))
  }
}
