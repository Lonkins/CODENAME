import CODENAMEKit
import Foundation
import QuartzCore

/// Hosts the core on its dedicated thread and drives it from a
/// CAMetalDisplayLink scheduled on that same thread (ADR 0003 video-master:
/// the display link is the clock; one retro_run per N vblanks, late-latch
/// blit into the update's drawable).
final class CoreDisplayLoop: NSObject, CAMetalDisplayLinkDelegate {
  private let layer: CAMetalLayer
  private let coreURL: URL
  private var session: CoreSession?
  private var presenter: MetalPresenter?
  private var vblanksPerFrame = 1
  private var vblankCount = 0

  init(layer: CAMetalLayer, coreURL: URL) {
    self.layer = layer
    self.coreURL = coreURL
    super.init()
  }

  /// Spawns the core thread; everything after this line happens there.
  func start() {
    let thread = Thread { [self] in
      setUpOnCoreThread()
      RunLoop.current.run()
    }
    thread.name = "CODENAME.core"
    thread.qualityOfService = .userInteractive
    thread.start()
  }

  private func setUpOnCoreThread() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let baseDirectory = support[0].appendingPathComponent("CODENAME", isDirectory: true)
    try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

    let environment = EnvironmentHandler(
      systemDirectory: baseDirectory.appendingPathComponent("System"),
      saveDirectory: baseDirectory.appendingPathComponent("Saves"))
    let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())

    do {
      let session = try CoreSession(coreURL: coreURL, policy: policy, environment: environment)
      try session.loadGame(path: nil)
      self.session = session
    } catch {
      NSLog("core load failed: \(error)")
      return
    }
    presenter = MetalPresenter()

    if let fps = session?.avInfo?.framesPerSecond {
      let refresh = 60.0  // ponytail: fixed assumption; query the display when pacing polish lands.
      if case .videoMaster(let vblanks) = FramePacer.mode(coreFPS: fps, displayRefresh: refresh) {
        vblanksPerFrame = vblanks
      }
    }

    let displayLink = CAMetalDisplayLink(metalLayer: layer)
    displayLink.delegate = self
    displayLink.add(to: .current, forMode: .default)
  }

  func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
    guard let session, let presenter else { return }

    vblankCount += 1
    if vblankCount % vblanksPerFrame == 0 {
      session.run(frames: 1)
      _ = session.drainAudioSamples()  // audio engine lands next; bound memory meanwhile
    }

    guard let frame = session.latestFrame, let aspect = session.avInfo?.aspectRatio else { return }
    let texture = update.drawable.texture
    let destination = IntegerScaler.destinationRect(
      contentWidth: frame.width, contentHeight: frame.height, aspectRatio: aspect,
      drawableWidth: texture.width, drawableHeight: texture.height, integerOnly: true)
    do {
      try presenter.render(frame: frame, into: texture, destination: destination)
      update.drawable.present()
    } catch {
      NSLog("render failed: \(error)")
    }
  }
}
