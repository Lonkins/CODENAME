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

  // MARK: - Frame clock (ADR 0003: what each mode means per vblank)

  @Test func videoMasterRunsOneFrameEveryVblank() {
    var clock = FramePacer.FrameClock(
      mode: .videoMaster(vblanksPerFrame: 1), coreFPS: 60, displayRefresh: 60)
    #expect((0..<4).map { _ in clock.framesDue() } == [1, 1, 1, 1])
  }

  @Test func videoMasterOnProMotionRunsEverySecondVblank() {
    var clock = FramePacer.FrameClock(
      mode: .videoMaster(vblanksPerFrame: 2), coreFPS: 60, displayRefresh: 120)
    #expect((0..<4).map { _ in clock.framesDue() } == [0, 1, 0, 1])
  }

  @Test func audioMasterRunsPALContentAtItsOwnRate() {
    // The bug this replaces: the fallback was decided and never implemented,
    // so a 50Hz core ran at 60 — 20% fast, with rate control clamped at
    // 0.5% and every overrun dropping audio.
    var clock = FramePacer.FrameClock(mode: .audioMaster, coreFPS: 50, displayRefresh: 60)
    let due = (0..<600).map { _ in clock.framesDue() }
    #expect(due.reduce(0, +) == 500)
    #expect(due.allSatisfy { $0 <= 1 })
  }

  @Test func audioMasterRunsCoresFasterThanTheDisplay() {
    var clock = FramePacer.FrameClock(mode: .audioMaster, coreFPS: 75, displayRefresh: 60)
    let total = (0..<600).reduce(0) { sum, _ in sum + clock.framesDue() }
    #expect(total == 750)
  }

  @Test func catchUpIsBounded() {
    // A core rate far above the display must not let one vblank ask for an
    // unbounded burst of frames after a hitch.
    var clock = FramePacer.FrameClock(mode: .audioMaster, coreFPS: 6000, displayRefresh: 60)
    #expect((0..<3).allSatisfy { _ in clock.framesDue() <= FramePacer.FrameClock.maxCatchUp })
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
