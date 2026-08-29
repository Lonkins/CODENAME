import Testing

@testable import CODENAMEKit

@Suite struct FramePacerTests {
  @Test func ntscOnSixtyHertzIsVideoMasterEveryVblank() {
    #expect(
      FramePacer.mode(coreFPS: 60.0988, displayRefresh: 60.0)
        == .videoMaster(vblanksPerFrame: 1))
  }

  @Test func sixtyOnProMotionRunsEverySecondVblank() {
    #expect(
      FramePacer.mode(coreFPS: 60.0, displayRefresh: 120.0)
        == .videoMaster(vblanksPerFrame: 2))
  }

  @Test func palOnSixtyHertzFallsBackToAudioMaster() {
    #expect(FramePacer.mode(coreFPS: 50.0, displayRefresh: 60.0) == .audioMaster)
  }

  @Test func palOnHundredHertzIsVideoMaster() {
    #expect(
      FramePacer.mode(coreFPS: 50.0, displayRefresh: 100.0)
        == .videoMaster(vblanksPerFrame: 2))
  }

  @Test func thirtyFPSCoreOnSixtyHertz() {
    #expect(
      FramePacer.mode(coreFPS: 30.0, displayRefresh: 60.0)
        == .videoMaster(vblanksPerFrame: 2))
  }

  @Test func balancedBufferKeepsBaseRatio() {
    #expect(FramePacer.resampleRatio(base: 1.5, occupancy: 0.5) == 1.5)
  }

  @Test func fullBufferSpeedsPlaybackWithinClamp() {
    let ratio = FramePacer.resampleRatio(base: 1.0, occupancy: 1.0)
    #expect(ratio == 1.005)
  }

  @Test func emptyBufferSlowsPlaybackWithinClamp() {
    let ratio = FramePacer.resampleRatio(base: 1.0, occupancy: 0.0)
    #expect(ratio == 0.995)
  }

  @Test func deviationScalesLinearlyWithOccupancy() {
    let ratio = FramePacer.resampleRatio(base: 1.0, occupancy: 0.75)
    #expect(abs(ratio - 1.0025) < 1e-9)
  }
}
