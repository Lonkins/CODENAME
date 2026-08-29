import CODENAMEKit
import Foundation
import QuartzCore

/// Hosts the core on its dedicated thread and drives it from a
/// CAMetalDisplayLink scheduled on that same thread (ADR 0003 video-master:
/// the display link is the clock; one retro_run per N vblanks, late-latch
/// blit into the update's drawable).
final class CoreDisplayLoop: NSObject, CAMetalDisplayLinkDelegate {
  let inputState = InputState()
  private let layer: CAMetalLayer
  private let coreURL: URL
  private let contentPath: String?
  private let displayRefresh: Double
  private var session: CoreSession?
  private var presenter: MetalPresenter?
  private var audioRing: SPSCRingBuffer?
  private var audioOutput: CoreAudioOutput?
  private var vblanksPerFrame = 1
  private var vblankCount = 0
  private var paceFrameCount = 0
  private var paceWindowStart = 0.0
  private var thread: Thread?
  private var displayLink: CAMetalDisplayLink?
  private var activity: NSObjectProtocol?
  private var coreThreadShouldRun = true  // flipped on the core thread itself, in teardown

  init(layer: CAMetalLayer, coreURL: URL, contentPath: String?, displayRefresh: Double) {
    self.layer = layer
    self.coreURL = coreURL
    self.contentPath = contentPath
    self.displayRefresh = displayRefresh
    super.init()
  }

  /// Spawns the core thread; everything after this line happens there.
  func start() {
    // Without this, App Nap suspends the display link once the user idles
    // (observed as a hard stall after ~4 callbacks). Session-scoped.
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical], reason: "emulation session")
    let thread = Thread { [self] in
      setUpOnCoreThread()
      // Foundation's run() re-enters after CFRunLoopStop; loop a stoppable form.
      while coreThreadShouldRun && RunLoop.current.run(mode: .default, before: .distantFuture) {}
      NSLog("core thread run loop exited")
    }
    thread.name = "CODENAME.core"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
  }

  /// Synchronous teardown on the core thread (order per ADR 0005): display
  /// link, audio, session (dlclose), then the run loop so the thread exits.
  func stop() {
    if let activity {
      ProcessInfo.processInfo.endActivity(activity)
      self.activity = nil
    }
    guard let thread, thread.isExecuting else { return }
    perform(#selector(tearDownOnCoreThread), on: thread, with: nil, waitUntilDone: true)
    self.thread = nil
  }

  @objc private func tearDownOnCoreThread() {
    displayLink?.invalidate()
    displayLink = nil
    audioOutput?.stop()
    audioOutput = nil
    session?.shutdown()
    session = nil
    presenter = nil
    audioRing = nil
    coreThreadShouldRun = false
    NSLog("session stopped after %d vblank callbacks", vblankCount)
    CFRunLoopStop(CFRunLoopGetCurrent())
  }

  private func setUpOnCoreThread() {
    AppPaths.ensureExists()
    let environment = EnvironmentHandler(
      systemDirectory: AppPaths.system, saveDirectory: AppPaths.saves)
    let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())

    do {
      let session = try CoreSession(
        coreURL: coreURL, policy: policy, environment: environment, inputState: inputState)
      try session.loadGame(path: contentPath)
      self.session = session
    } catch {
      NSLog("core load failed: \(error)")
      return
    }
    presenter = MetalPresenter()

    if let sampleRate = session?.avInfo?.audioSampleRate, sampleRate > 0 {
      // ~93ms of stereo at 44.1k; rate control holds it near half full.
      let ring = SPSCRingBuffer(capacity: 16384)
      let output = CoreAudioOutput(ring: ring, sourceRate: sampleRate)
      do {
        try output.start()
        audioRing = ring
        audioOutput = output
      } catch {
        NSLog("audio start failed: \(error)")
      }
    }

    if let fps = session?.avInfo?.framesPerSecond {
      let mode = FramePacer.mode(coreFPS: fps, displayRefresh: displayRefresh)
      if case .videoMaster(let vblanks) = mode {
        vblanksPerFrame = vblanks
      }
      NSLog(
        "pacing: core %.4ffps, display %.0fHz, %d vblank(s)/frame",
        fps, displayRefresh, vblanksPerFrame)
    }

    let displayLink = CAMetalDisplayLink(metalLayer: layer)
    displayLink.delegate = self
    displayLink.add(to: .current, forMode: .default)
    self.displayLink = displayLink
    NSLog(
      "display link armed, drawable %.0fx%.0f",
      layer.drawableSize.width, layer.drawableSize.height)
  }

  func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
    guard let session, let presenter else { return }

    vblankCount += 1
    if vblankCount == 1 {
      NSLog("display link first callback")
    }
    if vblankCount % vblanksPerFrame == 0 {
      session.run(frames: 1)
      let samples = session.drainAudioSamples()
      if let audioRing, let audioOutput {
        _ = audioRing.write(samples)  // overruns drop the newest; rate control prevents them
        audioOutput.updateRateControl()
      }

      paceFrameCount += 1
      let now = CACurrentMediaTime()
      if paceWindowStart == 0 { paceWindowStart = now }
      if now - paceWindowStart >= 5 {
        let fps = Double(paceFrameCount) / (now - paceWindowStart)
        NSLog("pace: %.2f core fps, ring %.2f", fps, audioRing?.occupancy ?? -1)
        paceFrameCount = 0
        paceWindowStart = now
      }
    }

    guard let frame = session.latestFrame, let aspect = session.avInfo?.aspectRatio else { return }
    let texture = update.drawable.texture
    let destination = IntegerScaler.destinationRect(
      contentWidth: frame.width, contentHeight: frame.height, aspectRatio: aspect,
      drawableWidth: texture.width, drawableHeight: texture.height, integerOnly: true)
    do {
      try presenter.render(
        frame: frame, into: texture, destination: destination, presenting: update.drawable)
    } catch {
      NSLog("render failed: \(error)")
    }
  }
}
