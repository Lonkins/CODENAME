/// Variable-ratio linear-interpolation resampler for interleaved stereo Int16
/// → interleaved stereo Float32. Runs on the audio render thread: no
/// allocation, no locks (scratch is preallocated; ring reads are lock-free).
/// Single consumer only, matching the ring's SPSC contract.
public final class StereoResampler {
  public private(set) var underrunFrames = 0

  private var previousLeft: Float = 0
  private var previousRight: Float = 0
  private var currentLeft: Float = 0
  private var currentRight: Float = 0
  private var fraction = 1.0
  private var pair = [Int16](repeating: 0, count: 2)

  public init() {}

  /// Fills `output` (interleaved L/R, output.count/2 frames), consuming input
  /// frames from `ring` at `step` input frames per output frame. Missing
  /// input becomes silence and is counted in `underrunFrames`.
  public func render(
    into output: UnsafeMutableBufferPointer<Float>, ring: SPSCRingBuffer, step: Double
  ) {
    let frames = output.count / 2
    for frame in 0..<frames {
      while fraction >= 1.0 {
        previousLeft = currentLeft
        previousRight = currentRight
        let read = pair.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        if read == 2 {
          currentLeft = Float(pair[0]) / 32768
          currentRight = Float(pair[1]) / 32768
        } else {
          currentLeft = 0
          currentRight = 0
          underrunFrames += 1
        }
        fraction -= 1.0
      }
      let mix = Float(fraction)
      output[frame * 2] = previousLeft + (currentLeft - previousLeft) * mix
      output[frame * 2 + 1] = previousRight + (currentRight - previousRight) * mix
      fraction += step
    }
  }
}
