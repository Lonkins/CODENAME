import IOSurface
import Metal
import Testing

@testable import CODENAMEKit

private let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

@Suite(.enabled(if: hasMetalDevice))
struct MetalPresenterTests {
  private func makeTarget(_ device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)
  }

  private func pixel(of texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 4)
    out.withUnsafeMutableBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      texture.getBytes(
        base, bytesPerRow: 4,
        from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
    }
    return out
  }

  @Test func rendersFrameIntoDestinationWithBlackBorders() throws {
    let presenter = try #require(MetalPresenter())
    let target = try #require(makeTarget(presenter.device, width: 64, height: 48))

    // 2x2 solid red XRGB8888 frame.
    let redPixel: [UInt8] = [0x00, 0x00, 0xFF, 0x00]
    let frame = CoreSession.VideoFrame(
      width: 2, height: 2, pitch: 8, pixelFormat: .xrgb8888,
      bytes: Array([redPixel, redPixel, redPixel, redPixel].joined()))

    // Integer scale: k = min(32, 24) = 24 → 48x48 at x=8, y=0.
    let destination = IntegerScaler.destinationRect(
      contentWidth: 2, contentHeight: 2, aspectRatio: 1.0,
      drawableWidth: 64, drawableHeight: 48, integerOnly: true)
    #expect(destination == IntegerScaler.Rect(x: 8, y: 0, width: 48, height: 48))

    try presenter.render(frame: frame, into: target, destination: destination)

    #expect(pixel(of: target, x: 32, y: 24) == [0, 0, 255, 255])
    #expect(pixel(of: target, x: 2, y: 24) == [0, 0, 0, 255])
    #expect(pixel(of: target, x: 62, y: 24) == [0, 0, 0, 255])
  }

  @Test func rendersFrameRegionOfMaxSizedSurface() throws {
    // Helper path: a 4x4 surface (max geometry) holding a 2x2 green frame in
    // its top-left corner — only that region may be sampled.
    let presenter = try #require(MetalPresenter())
    let target = try #require(makeTarget(presenter.device, width: 16, height: 16))
    let surface = try #require(CoreHostWire.makeFrameSurface(width: 4, height: 4))

    IOSurfaceLock(surface, [], nil)
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let rowBytes = IOSurfaceGetBytesPerRow(surface)
    for row in 0..<4 {
      for column in 0..<4 {
        let offset = row * rowBytes + column * 4
        let inFrame = row < 2 && column < 2
        // BGRA: green inside the frame region, white garbage outside it.
        base[offset] = inFrame ? 0 : 255
        base[offset + 1] = inFrame ? 255 : 255
        base[offset + 2] = inFrame ? 0 : 255
        base[offset + 3] = 255
      }
    }
    IOSurfaceUnlock(surface, [], nil)

    try presenter.render(
      surface: surface, frameWidth: 2, frameHeight: 2, into: target,
      destination: IntegerScaler.Rect(x: 0, y: 0, width: 16, height: 16))

    // Every corner of the target must be frame green — the garbage outside
    // the 2x2 region never appears.
    #expect(pixel(of: target, x: 1, y: 1) == [0, 255, 0, 255])
    #expect(pixel(of: target, x: 14, y: 1) == [0, 255, 0, 255])
    #expect(pixel(of: target, x: 1, y: 14) == [0, 255, 0, 255])
    #expect(pixel(of: target, x: 14, y: 14) == [0, 255, 0, 255])
  }

  @Test func reusesTextureAcrossSameSizeFrames() throws {
    let presenter = try #require(MetalPresenter())
    let target = try #require(makeTarget(presenter.device, width: 16, height: 16))
    let frame = CoreSession.VideoFrame(
      width: 2, height: 2, pitch: 4, pixelFormat: .rgb565,
      bytes: [0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8])
    let destination = IntegerScaler.Rect(x: 0, y: 0, width: 16, height: 16)

    try presenter.render(frame: frame, into: target, destination: destination)
    try presenter.render(frame: frame, into: target, destination: destination)
    #expect(pixel(of: target, x: 8, y: 8) == [0, 0, 255, 255])
  }
}
