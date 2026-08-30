import CODENAMEKit
import Foundation
import QuartzCore

/// Drives a helper-hosted core session from the app (ADR 0007): the same
/// video-master pacing as CoreDisplayLoop, but frames run out-of-process —
/// per vblank group one runFramesShared crosses the wire, and the drawable
/// late-latches whatever the shared IOSurface holds. A slow reply degrades
/// to frame repeat, never to a blocked callback.
final class HelperDisplayLoop: NSObject, CAMetalDisplayLinkDelegate {
  var inputState: InputState { session.inputState }
  private let layer: CAMetalLayer
  private let coreURL: URL
  private let contentPath: String?
  private let displayRefresh: Double
  private var connection: NSXPCConnection?
  private let session: HelperSession
  private var presenter: MetalPresenter?
  private var audioRing: SPSCRingBuffer?
  private var audioOutput: CoreAudioOutput?
  private var aspectRatio = 4.0 / 3.0
  private var vblanksPerFrame = 1
  private var vblankCount = 0
  private var paceFrameCount = 0
  private var paceWindowStart = 0.0
  private var thread: Thread?
  private var displayLink: CAMetalDisplayLink?
  private var activity: NSObjectProtocol?
  private var coreThreadShouldRun = true
  private let saveStore = SaveRAMStore()
  private let stateStore = SaveStateStore()
  private var saveIdentity: (core: String, content: String)?
  private var lastFlushedSaveRAM: Data?
  private var framesSinceFlush = 0

  let displaySettings: LiveDisplaySettings

  /// Fails only when the helper connection can't even be constructed; load
  /// failures surface as a dead session (no frames, logged) per ADR 0001's
  /// fallible-session design.
  init?(
    layer: CAMetalLayer, coreURL: URL, contentPath: String?, displayRefresh: Double,
    displaySettings: LiveDisplaySettings
  ) {
    let connection = NSXPCConnection(serviceName: "dev.CODENAME.CoreHost")
    connection.remoteObjectInterface = CoreHostWire.interface()
    connection.resume()
    self.connection = connection
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      NSLog("helper session error: \(error.localizedDescription)")
    }
    guard let remote = proxy as? CoreHostProtocol else {
      connection.invalidate()
      return nil
    }
    self.session = HelperSession(proxy: remote)
    self.layer = layer
    self.coreURL = coreURL
    self.contentPath = contentPath
    self.displayRefresh = displayRefresh
    self.displaySettings = displaySettings
    super.init()
  }

  func start() {
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical], reason: "helper emulation session")
    let thread = Thread { [self] in
      setUpOnLoopThread()
      while coreThreadShouldRun && RunLoop.current.run(mode: .default, before: .distantFuture) {}
      NSLog("helper loop thread exited")
    }
    thread.name = "CODENAME.helper-loop"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
  }

  func stop() {
    if let activity {
      ProcessInfo.processInfo.endActivity(activity)
      self.activity = nil
    }
    guard let thread, thread.isExecuting else { return }
    perform(#selector(tearDownOnLoopThread), on: thread, with: nil, waitUntilDone: true)
    self.thread = nil
  }

  @objc private func tearDownOnLoopThread() {
    displayLink?.invalidate()
    displayLink = nil
    audioOutput?.stop()
    audioOutput = nil
    flushSaveRAM()
    session.close()
    connection?.invalidate()
    connection = nil
    presenter = nil
    audioRing = nil
    coreThreadShouldRun = false
    NSLog("helper session stopped after %d vblank callbacks", vblankCount)
    CFRunLoopStop(CFRunLoopGetCurrent())
  }

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
    guard let saveIdentity, let snapshot = session.serializeState() else { return }
    do {
      try stateStore.save(
        [UInt8](snapshot), coreName: saveIdentity.core, contentName: saveIdentity.content,
        slot: slot.intValue)
      NSLog("helper state saved to slot %d (%d bytes)", slot.intValue, snapshot.count)
    } catch {
      NSLog("helper state save failed: \(error)")
    }
  }

  @objc private func performLoadState(_ slot: NSNumber) {
    guard let saveIdentity,
      let bytes = stateStore.load(
        coreName: saveIdentity.core, contentName: saveIdentity.content, slot: slot.intValue)
    else {
      NSLog("helper state slot %d is empty", slot.intValue)
      return
    }
    if session.unserializeState(Data(bytes)) {
      NSLog("helper state loaded from slot %d", slot.intValue)
    } else {
      NSLog("helper state load failed")
    }
  }

  private func flushSaveRAM() {
    guard let saveIdentity, let snapshot = session.saveRAMSnapshot(),
      snapshot != lastFlushedSaveRAM
    else { return }
    do {
      try saveStore.save(
        [UInt8](snapshot), coreName: saveIdentity.core, contentName: saveIdentity.content)
      lastFlushedSaveRAM = snapshot
    } catch {
      NSLog("helper save RAM flush failed: \(error)")
    }
  }

  private func setUpOnLoopThread() {
    AppPaths.ensureExists()
    guard
      let av = session.open(
        corePath: coreURL.path, contentPath: contentPath,
        systemDirectory: AppPaths.system.path, saveDirectory: AppPaths.saves.path)
    else {
      NSLog("helper core load failed")
      return
    }
    presenter = MetalPresenter()
    if av.aspectRatio > 0 { aspectRatio = av.aspectRatio }

    if let contentPath {
      let identity = (
        core: coreURL.deletingPathExtension().lastPathComponent,
        content: URL(fileURLWithPath: contentPath).deletingPathExtension().lastPathComponent
      )
      saveIdentity = identity
      if let existing = saveStore.load(coreName: identity.core, contentName: identity.content),
        session.restoreSaveRAM(Data(existing))
      {
        lastFlushedSaveRAM = Data(existing)
        NSLog("helper save RAM restored (%d bytes)", existing.count)
      }
    }

    if av.audioSampleRate > 0 {
      let ring = SPSCRingBuffer(capacity: 16384)
      let output = CoreAudioOutput(ring: ring, sourceRate: av.audioSampleRate)
      do {
        try output.start()
        audioRing = ring
        audioOutput = output
      } catch {
        NSLog("helper audio start failed: \(error)")
      }
    }

    let mode = FramePacer.mode(coreFPS: av.framesPerSecond, displayRefresh: displayRefresh)
    if case .videoMaster(let vblanks) = mode {
      vblanksPerFrame = vblanks
    }
    NSLog(
      "helper pacing: core %.4ffps, display %.0fHz, %d vblank(s)/frame",
      av.framesPerSecond, displayRefresh, vblanksPerFrame)

    let displayLink = CAMetalDisplayLink(metalLayer: layer)
    displayLink.delegate = self
    displayLink.add(to: .current, forMode: .default)
    self.displayLink = displayLink
    NSLog("helper display link armed")
  }

  func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
    guard let presenter, let surface = session.surface else { return }

    vblankCount += 1
    if vblankCount == 1 {
      NSLog("helper display link first callback")
    }
    if vblankCount % vblanksPerFrame == 0 {
      let ring = audioRing
      let output = audioOutput
      _ = session.runFrame { audio in
        guard let ring else { return }
        audio.withUnsafeBytes { raw in
          let samples = raw.bindMemory(to: Int16.self)
          _ = ring.write(Array(samples))
        }
        output?.updateRateControl()
      }

      framesSinceFlush += 1
      if framesSinceFlush >= 600 {
        framesSinceFlush = 0
        flushSaveRAM()
      }

      // Positive pace signal, same discipline as the in-process loop:
      // silence is never proof a loop is alive.
      paceFrameCount += 1
      let now = CACurrentMediaTime()
      if paceWindowStart == 0 { paceWindowStart = now }
      if now - paceWindowStart >= 5 {
        let fps = Double(paceFrameCount) / (now - paceWindowStart)
        NSLog("helper pace: %.2f core fps, ring %.2f", fps, audioRing?.occupancy ?? -1)
        paceFrameCount = 0
        paceWindowStart = now
      }
    }

    let size = session.latestFrameSize
    guard size.width > 0, size.height > 0 else { return }
    let texture = update.drawable.texture
    let destination = IntegerScaler.destinationRect(
      contentWidth: size.width, contentHeight: size.height, aspectRatio: aspectRatio,
      drawableWidth: texture.width, drawableHeight: texture.height,
      integerOnly: displaySettings.integerScale)
    do {
      try presenter.render(
        surface: surface, frameWidth: size.width, frameHeight: size.height,
        into: texture, destination: destination, presenting: update.drawable)
    } catch {
      NSLog("helper render failed: \(error)")
    }
  }
}
