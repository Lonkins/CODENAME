import AVFoundation
import Synchronization

/// Plays core audio: an AVAudioSourceNode pulls the SPSC ring through the
/// resampler on the audio render thread. The step (input frames per output
/// frame) is published atomically by the core thread's rate control.
/// @unchecked Sendable: resampler is touched only by the render thread,
/// engine control only by the owning core thread; the atomic bridges them.
public final class CoreAudioOutput: @unchecked Sendable {
  public enum AudioError: Error {
    case formatUnavailable
  }

  private let engine = AVAudioEngine()
  private let ring: SPSCRingBuffer
  private let resampler = StereoResampler()
  private let sourceRate: Double
  private let stepBits = Atomic<UInt64>(1.0.bitPattern)
  private var deviceRate = 48000.0

  public init(ring: SPSCRingBuffer, sourceRate: Double) {
    self.ring = ring
    self.sourceRate = sourceRate
  }

  public func start() throws {
    deviceRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    guard deviceRate > 0,
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: deviceRate, channels: 2, interleaved: true)
    else { throw AudioError.formatUnavailable }
    stepBits.store((sourceRate / deviceRate).bitPattern, ordering: .relaxed)

    let node = AVAudioSourceNode(format: format) {
      [weak self] _, _, frameCount, audioBufferList in
      guard let self else { return noErr }
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let data = buffers[0].mData else { return noErr }
      let output = UnsafeMutableBufferPointer(
        start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount) * 2)
      let step = Double(bitPattern: self.stepBits.load(ordering: .relaxed))
      self.resampler.render(into: output, ring: self.ring, step: step)
      return noErr
    }
    engine.attach(node)
    engine.connect(node, to: engine.outputNode, format: format)
    try engine.start()
  }

  public func stop() {
    engine.stop()
  }

  /// Called from the core thread each frame: dynamic rate control (ADR 0003).
  public func updateRateControl() {
    let step = FramePacer.resampleRatio(base: sourceRate / deviceRate, occupancy: ring.occupancy)
    stepBits.store(step.bitPattern, ordering: .relaxed)
  }
}
