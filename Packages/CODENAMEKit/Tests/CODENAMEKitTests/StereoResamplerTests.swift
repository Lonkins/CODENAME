import Testing

@testable import CODENAMEKit

@Suite struct StereoResamplerTests {
  private func fill(_ ring: SPSCRingBuffer, leftValues: [Int16]) {
    var interleaved: [Int16] = []
    for value in leftValues {
      interleaved.append(value)
      interleaved.append(-value)
    }
    #expect(ring.write(interleaved) == interleaved.count)
  }

  private func render(
    _ resampler: StereoResampler, _ ring: SPSCRingBuffer, frames: Int, step: Double
  ) -> [Float] {
    var out = [Float](repeating: .nan, count: frames * 2)
    out.withUnsafeMutableBufferPointer { resampler.render(into: $0, ring: ring, step: step) }
    return out
  }

  @Test func unityStepPassesThroughWithOneFrameLatency() {
    let ring = SPSCRingBuffer(capacity: 64)
    let resampler = StereoResampler()
    fill(ring, leftValues: [100, 200, 300, 400])

    let out = render(resampler, ring, frames: 4, step: 1.0)
    let left = [out[0], out[2], out[4], out[6]].map { $0 * 32768 }
    #expect(left == [0, 100, 200, 300])
    #expect(out[3] * 32768 == -100)
    #expect(resampler.underrunFrames == 0)
  }

  @Test func halfStepInterpolatesBetweenInputFrames() {
    let ring = SPSCRingBuffer(capacity: 64)
    let resampler = StereoResampler()
    fill(ring, leftValues: [100, 200])

    let out = render(resampler, ring, frames: 4, step: 0.5)
    let left = [out[0], out[2], out[4], out[6]].map { $0 * 32768 }
    #expect(left == [0, 50, 100, 150])
  }

  @Test func doubleStepDecimates() {
    let ring = SPSCRingBuffer(capacity: 64)
    let resampler = StereoResampler()
    fill(ring, leftValues: [100, 200, 300, 400, 500])

    let out = render(resampler, ring, frames: 3, step: 2.0)
    let left = [out[0], out[2], out[4]].map { $0 * 32768 }
    #expect(left == [0, 200, 400])
  }

  @Test func underrunProducesSilenceAndCounts() {
    let ring = SPSCRingBuffer(capacity: 64)
    let resampler = StereoResampler()
    fill(ring, leftValues: [100, 200])

    let out = render(resampler, ring, frames: 4, step: 1.0)
    let left = [out[0], out[2], out[4], out[6]].map { $0 * 32768 }
    #expect(left == [0, 100, 200, 0])
    #expect(resampler.underrunFrames == 2)
  }

  @Test func stateCarriesAcrossRenderCalls() {
    let ring = SPSCRingBuffer(capacity: 64)
    let resampler = StereoResampler()
    fill(ring, leftValues: [100, 200, 300, 400])

    let first = render(resampler, ring, frames: 2, step: 1.0)
    #expect([first[0], first[2]].map { $0 * 32768 } == [0, 100])

    let second = render(resampler, ring, frames: 2, step: 1.0)
    #expect([second[0], second[2]].map { $0 * 32768 } == [200, 300])
  }
}
