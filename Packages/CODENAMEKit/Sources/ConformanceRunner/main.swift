import CODENAMEKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Conformance check as a plain executable so it runs on toolchains without
// the swift-testing runtime. Content paths come from arguments only.
// Usage: conformance-runner --core <dylib> --content <file> [--frames N] [--expected-hash H]
// [--list-options] prints every core option the core declared.

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
  exit(1)
}

var core: String?
var content: String?
var frames = 300
var expectedHash: String?
var dumpPath: String?
var useHelper = false
var listOptions = false
var systemDir = FileManager.default.temporaryDirectory.path

var arguments = Array(CommandLine.arguments.dropFirst()).makeIterator()
while let flag = arguments.next() {
  switch flag {
  case "--core": core = arguments.next()
  case "--content": content = arguments.next()
  case "--frames": frames = arguments.next().flatMap(Int.init) ?? frames
  case "--expected-hash": expectedHash = arguments.next()
  case "--dump-frame": dumpPath = arguments.next()
  case "--helper": useHelper = true
  case "--list-options": listOptions = true
  case "--system-dir": systemDir = arguments.next() ?? systemDir
  default: fail("unknown argument \(flag)")
  }
}

guard let core, let content else {
  fail("usage: conformance-runner --core <dylib> --content <file> [--frames N] [--expected-hash H]")
}

func hash(_ frame: CoreSession.VideoFrame) -> String {
  SHA256.hash(data: Data(frame.bytes)).map { String(format: "%02x", $0) }.joined()
}

// Framebuffer → PNG, straight from core memory: works headless, no window
// server involved.
func writePNG(_ frame: CoreSession.VideoFrame, to path: String) {
  guard
    let bgra = PixelConverter.toBGRA8(
      bytes: frame.bytes, width: frame.width, height: frame.height,
      pitch: frame.pitch, format: frame.pixelFormat)
  else {
    print("frame geometry is not renderable: \(frame.width)x\(frame.height) pitch \(frame.pitch)")
    return
  }
  let bitmapInfo = CGBitmapInfo(
    rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
  guard let provider = CGDataProvider(data: Data(bgra) as CFData),
    let image = CGImage(
      width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent),
    let destination = CGImageDestinationCreateWithURL(
      URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fail("could not encode frame PNG") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("could not write \(path)") }
  print("frame dumped: \(path)")
}

let coreURL = URL(fileURLWithPath: core)
let environment = EnvironmentHandler(
  systemDirectory: URL(fileURLWithPath: systemDir),
  saveDirectory: FileManager.default.temporaryDirectory)
let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())

// --helper: the same battery through the XPC serialization path (loopback
// host — full NSXPCConnection machinery, no launchd needed in a bare tool).
func runViaHelper(
  coreURL: URL, content: String, frames: Int, expectedHash: String?, systemDir: String
) {
  let host = LoopbackCoreHost()
  guard let proxy = host.proxy(errorHandler: { fail("xpc error: \($0.localizedDescription)") })
  else { fail("no helper proxy") }

  func waitFrames(_ count: Int) -> (bytes: Data, wireCode: Int, audio: Data) {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: (Data, Int, Data) = (Data(), -1, Data())
    proxy.runFrames(count) { bytes, _, _, _, code, audio in
      result = (bytes, code, audio)
      semaphore.signal()
    }
    semaphore.wait()
    return result
  }

  let openSemaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var av: (ok: Bool, fps: Double, rate: Double) = (false, 0, 0)
  proxy.openSession(
    corePath: coreURL.path, contentPath: content, contentBytes: Data(),
    disc: Data(), contentHandles: [],
    systemDirectory: systemDir,
    saveDirectory: FileManager.default.temporaryDirectory.path,
    options: Data()
  ) { ok, _, _, _, _, _, fps, rate in
    av = (ok, fps, rate)
    openSemaphore.signal()
  }
  openSemaphore.wait()
  guard av.ok else { fail("helper failed to open session") }
  print("helper session: \(av.fps)fps, \(av.rate)Hz")

  let main = waitFrames(frames)
  let digest = SHA256.hash(data: main.bytes).map { String(format: "%02x", $0) }.joined()
  print("helper frames: \(frames), framebuffer sha256: \(digest)")
  let audioSamples = main.audio.count / MemoryLayout<Int16>.size
  let expectedSamples = Double(frames) * av.rate / av.fps * 2
  let ratio = Double(audioSamples) / expectedSamples
  print("helper audio: \(audioSamples) samples (\(String(format: "%.3f", ratio))x expected)")
  guard ratio > 0.9, ratio < 1.1 else { fail("helper audio count off by >10%") }

  let stateSemaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var snapshot = Data()
  proxy.serializeState { data in
    snapshot = data
    stateSemaphore.signal()
  }
  stateSemaphore.wait()
  guard !snapshot.isEmpty else { fail("helper serialize returned empty") }

  let firstHash = SHA256.hash(data: waitFrames(30).bytes)
    .map { String(format: "%02x", $0) }.joined()
  let restoreSemaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var restored = false
  proxy.unserializeState(snapshot) { ok in
    restored = ok
    restoreSemaphore.signal()
  }
  restoreSemaphore.wait()
  guard restored else { fail("helper unserialize failed") }
  let replayHash = SHA256.hash(data: waitFrames(30).bytes)
    .map { String(format: "%02x", $0) }.joined()
  guard replayHash == firstHash else { fail("helper save-state round trip diverged") }
  print("helper save-state: round trip deterministic over 30 frames")

  if let expectedHash {
    guard digest == expectedHash else { fail("helper hash mismatch: expected \(expectedHash)") }
    print("helper hash: matches expected")
  }
  print("PASS (helper)")
  let closeSemaphore = DispatchSemaphore(value: 0)
  proxy.closeSession { closeSemaphore.signal() }
  closeSemaphore.wait()
}

if useHelper {
  runViaHelper(
    coreURL: coreURL, content: content, frames: frames, expectedHash: expectedHash,
    systemDir: systemDir)
  exit(0)
}

do {
  let session = try CoreSession(coreURL: coreURL, policy: policy, environment: environment)
  defer { session.shutdown() }
  try session.loadGame(path: content)
  guard let av = session.avInfo else { fail("no av info after load") }
  print("core: \(coreURL.lastPathComponent)")
  let size = "\(av.baseSize.width)x\(av.baseSize.height)"
  print("av: \(size) @ \(av.framesPerSecond)fps, \(av.audioSampleRate)Hz")
  let declared = environment.options.definitions
  print("options: \(declared.count) declared")
  if listOptions {
    for option in declared {
      print("  \(option.key) = \(option.defaultValue) of \(option.values.count)")
    }
  }

  session.run(frames: frames)
  let audioSamples = session.drainAudioSamples().count
  guard let frame = session.latestFrame else { fail("no frame after \(frames) frames") }
  let digest = hash(frame)
  print("frames: \(frames), framebuffer sha256: \(digest)")
  if let dumpPath {
    writePNG(frame, to: dumpPath)
  }

  let expectedSamples = Double(frames) * av.audioSampleRate / av.framesPerSecond * 2
  let audioRatio = Double(audioSamples) / expectedSamples
  print("audio: \(audioSamples) samples (\(String(format: "%.3f", audioRatio))x expected)")
  guard audioRatio > 0.9, audioRatio < 1.1 else { fail("audio sample count off by >10%") }

  let snapshot = try session.serialize()
  session.run(frames: 30)
  guard let after = session.latestFrame else { fail("no frame after extra run") }
  let firstHash = hash(after)
  try session.unserialize(snapshot)
  session.run(frames: 30)
  guard let replay = session.latestFrame else { fail("no frame after replay") }
  guard hash(replay) == firstHash else { fail("save-state round trip diverged") }
  print("save-state: round trip deterministic over 30 frames")

  if let expectedHash {
    guard digest == expectedHash else { fail("hash mismatch: expected \(expectedHash)") }
    print("hash: matches expected")
  }
  print("PASS")
} catch {
  fail("\(error)")
}
