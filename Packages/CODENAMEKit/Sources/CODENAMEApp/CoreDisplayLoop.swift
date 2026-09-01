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
  /// Which library entry this session's saves belong to (ADR 0004).
  private let entryID: UUID?
  private let displayRefresh: Double
  private var session: CoreSession?
  private var presenter: MetalPresenter?
  private var audioRing: SPSCRingBuffer?
  private var audioOutput: CoreAudioOutput?
  private var frameClock = FramePacer.FrameClock(
    mode: .videoMaster(vblanksPerFrame: 1), coreFPS: 60, displayRefresh: 60)
  private var vblankCount = 0
  private var paceFrameCount = 0
  private var paceWindowStart = 0.0
  private var thread: Thread?
  private var displayLink: CAMetalDisplayLink?
  private var activity: NSObjectProtocol?
  private var coreThreadShouldRun = true  // flipped on the core thread itself, in teardown
  private let saveStore = SaveRAMStore()
  private let stateStore = SaveStateStore()
  /// The library entry this session belongs to; nil for sessions with
  /// no entry (a user-supplied core picking its own content), which
  /// simply persist nothing.
  private var saveIdentity: UUID?
  private var lastFlushedSaveRAM: [UInt8]?
  private var framesSinceFlush = 0

  let displaySettings: LiveDisplaySettings

  init(
    layer: CAMetalLayer, coreURL: URL, contentPath: String?, entryID: UUID?,
    displayRefresh: Double, displaySettings: LiveDisplaySettings
  ) {
    self.layer = layer
    self.coreURL = coreURL
    self.contentPath = contentPath
    self.entryID = entryID
    self.displayRefresh = displayRefresh
    self.displaySettings = displaySettings
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
    flushSaveRAM()
    session?.shutdown()
    session = nil
    presenter = nil
    audioRing = nil
    coreThreadShouldRun = false
    NSLog("session stopped after %d vblank callbacks", vblankCount)
    CFRunLoopStop(CFRunLoopGetCurrent())
  }

  /// Main-thread entry points; work hops to the core thread asynchronously.
  func requestSaveState(slot: Int) {
    guard let thread, thread.isExecuting else { return }
    perform(
      #selector(performSaveState(_:)), on: thread, with: NSNumber(value: slot),
      waitUntilDone: false)
  }

  func requestLoadState(slot: Int) {
    guard let thread, thread.isExecuting else { return }
    perform(
      #selector(performLoadState(_:)), on: thread, with: NSNumber(value: slot),
      waitUntilDone: false)
  }

  @objc private func performSaveState(_ slot: NSNumber) {
    guard let saveIdentity, let session else { return }
    do {
      let snapshot = try session.serialize()
      try stateStore.save(
        snapshot, entryID: saveIdentity,
        slot: slot.intValue)
      NSLog("state saved to slot %d (%d bytes)", slot.intValue, snapshot.count)
    } catch {
      NSLog("state save failed: \(error)")
    }
  }

  @objc private func performLoadState(_ slot: NSNumber) {
    guard let saveIdentity, let session else { return }
    guard
      let bytes = stateStore.load(
        entryID: saveIdentity, slot: slot.intValue)
    else {
      NSLog("state slot %d is empty", slot.intValue)
      return
    }
    do {
      try session.unserialize(bytes)
      NSLog("state loaded from slot %d", slot.intValue)
    } catch {
      NSLog("state load failed: \(error)")
    }
  }

  private func flushSaveRAM() {
    guard let saveIdentity, let snapshot = session?.saveRAMSnapshot(),
      snapshot != lastFlushedSaveRAM
    else { return }
    do {
      try saveStore.save(snapshot, entryID: saveIdentity)
      lastFlushedSaveRAM = snapshot
    } catch {
      NSLog("save RAM flush failed: \(error)")
    }
  }

  private func setUpOnCoreThread() {
    AppPaths.ensureExists()
    let environment = EnvironmentHandler(
      systemDirectory: AppPaths.system, saveDirectory: AppPaths.saves)
    // Derived from the bundle, never from the candidate: a policy built
    // from the core's own parent directory compares a path to itself and
    // validates nothing (ADR 0001).
    let policy = CoreTrustPolicy(allowedDirectory: ContentRouter.bundledPlugInsDirectory)

    // Seeded before the session exists: cores declare their options during
    // retro_set_environment, which runs inside CoreSession's initializer.
    let optionsURL = AppPaths.optionsFile(forCore: coreURL)
    environment.options.prefer((try? CoreOptionsStore.load(from: optionsURL)) ?? [:])

    do {
      let session = try CoreSession(
        coreURL: coreURL, policy: policy, environment: environment, inputState: inputState)
      try session.loadGame(path: contentPath)
      self.session = session
    } catch {
      NSLog("core load failed: \(error)")
      return
    }

    // Written back so the file exists with every option the core offers,
    // which is what makes it editable between sessions.
    do {
      try CoreOptionsStore.save(environment.options.selectedValues, to: optionsURL)
    } catch {
      NSLog("core options save failed: \(error)")
    }
    presenter = MetalPresenter()

    if let entryID {
      saveIdentity = entryID
      if let existing = saveStore.load(entryID: entryID),
        session?.restoreSaveRAM(existing) == true
      {
        lastFlushedSaveRAM = existing
        NSLog("save RAM restored (%d bytes)", existing.count)
      }
    }

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
      frameClock = FramePacer.FrameClock(
        mode: mode, coreFPS: fps, displayRefresh: displayRefresh)
      NSLog(
        "pacing: core %.4ffps, display %.0fHz, %.4f frame(s)/vblank, %@",
        fps, displayRefresh, frameClock.framesPerVblank,
        mode == .audioMaster ? "audio-master" : "video-master")
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
    let framesDue = frameClock.framesDue()
    if framesDue > 0 {
      session.run(frames: framesDue)
      let samples = session.drainAudioSamples()
      if let audioRing, let audioOutput {
        _ = audioRing.write(samples)  // overruns drop the newest; rate control prevents them
        audioOutput.updateRateControl()
      }

      framesSinceFlush += 1
      if framesSinceFlush >= 600 {  // ~10s: cheap insurance against hard exits
        framesSinceFlush = 0
        flushSaveRAM()
      }

      paceFrameCount += framesDue
      let now = CACurrentMediaTime()
      if paceWindowStart == 0 { paceWindowStart = now }
      if now - paceWindowStart >= 5 {
        let fps = Double(paceFrameCount) / (now - paceWindowStart)
        NSLog("pace: %.2f core fps, ring %.2f", fps, audioRing?.occupancy ?? -1)
        paceFrameCount = 0
        paceWindowStart = now
      }
    }

    guard let frame = session.latestFrame, let aspect = session.avInfo?.aspectRatio,
      frame.width > 0, frame.height > 0
    else { return }
    let texture = update.drawable.texture
    let integerOnly = displaySettings.integerScale
    let destination = IntegerScaler.destinationRect(
      contentWidth: frame.width, contentHeight: frame.height, aspectRatio: aspect,
      drawableWidth: texture.width, drawableHeight: texture.height, integerOnly: integerOnly)
    do {
      try presenter.render(
        frame: frame, into: texture, destination: destination, presenting: update.drawable)
    } catch {
      NSLog("render failed: \(error)")
    }
  }
}
