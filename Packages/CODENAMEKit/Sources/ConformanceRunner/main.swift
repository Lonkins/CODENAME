import CODENAMEKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Conformance check as a plain executable so it runs on toolchains without
// the swift-testing runtime. Content paths come from arguments only.
// Usage: conformance-runner --core <dylib> --content <file> [--frames N] [--expected-hash H]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
  exit(1)
}

var core: String?
var content: String?
var frames = 300
var expectedHash: String?
var dumpPath: String?

var arguments = Array(CommandLine.arguments.dropFirst()).makeIterator()
while let flag = arguments.next() {
  switch flag {
  case "--core": core = arguments.next()
  case "--content": content = arguments.next()
  case "--frames": frames = arguments.next().flatMap(Int.init) ?? frames
  case "--expected-hash": expectedHash = arguments.next()
  case "--dump-frame": dumpPath = arguments.next()
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
  let bgra = PixelConverter.toBGRA8(
    bytes: frame.bytes, width: frame.width, height: frame.height,
    pitch: frame.pitch, format: frame.pixelFormat)
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
  systemDirectory: FileManager.default.temporaryDirectory,
  saveDirectory: FileManager.default.temporaryDirectory)
let policy = CoreTrustPolicy(allowedDirectory: coreURL.deletingLastPathComponent())

do {
  let session = try CoreSession(coreURL: coreURL, policy: policy, environment: environment)
  defer { session.shutdown() }
  try session.loadGame(path: content)
  guard let av = session.avInfo else { fail("no av info after load") }
  print("core: \(coreURL.lastPathComponent)")
  let size = "\(av.baseSize.width)x\(av.baseSize.height)"
  print("av: \(size) @ \(av.framesPerSecond)fps, \(av.audioSampleRate)Hz")

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
