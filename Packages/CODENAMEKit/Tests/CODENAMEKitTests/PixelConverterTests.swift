import Testing

@testable import CODENAMEKit

@Suite struct PixelConverterTests {
  private func bgra(
    _ bytes: [UInt8], _ format: LibretroPixelFormat,
    width: Int = 1, height: Int = 1, pitch: Int? = nil
  ) -> [UInt8]? {
    PixelConverter.toBGRA8(
      bytes: bytes, width: width, height: height,
      pitch: pitch ?? width * format.bytesPerPixel, format: format)
  }

  @Test func rgb565Primaries() {
    // Little-endian u16s: red 0xF800, green 0x07E0, blue 0x001F.
    #expect(bgra([0x00, 0xF8], .rgb565) == [0, 0, 255, 255])
    #expect(bgra([0xE0, 0x07], .rgb565) == [0, 255, 0, 255])
    #expect(bgra([0x1F, 0x00], .rgb565) == [255, 0, 0, 255])
  }

  @Test func rgb565BitExpansion() {
    // red5 = 16 → (16<<3)|(16>>2) = 132; green6 = 32 → (32<<2)|(32>>4) = 130.
    let red16 = UInt16(16) << 11
    #expect(bgra([UInt8(red16 & 0xFF), UInt8(red16 >> 8)], .rgb565) == [0, 0, 132, 255])
    let green32 = UInt16(32) << 5
    #expect(bgra([UInt8(green32 & 0xFF), UInt8(green32 >> 8)], .rgb565) == [0, 130, 0, 255])
  }

  @Test func zeroRGB1555Primaries() {
    // red 0x7C00, green 0x03E0, blue 0x001F; top bit ignored.
    #expect(bgra([0x00, 0x7C], .zeroRGB1555) == [0, 0, 255, 255])
    #expect(bgra([0xE0, 0x03], .zeroRGB1555) == [0, 255, 0, 255])
    #expect(bgra([0x1F, 0x00], .zeroRGB1555) == [255, 0, 0, 255])
    #expect(bgra([0x00, 0xFC], .zeroRGB1555) == [0, 0, 255, 255])
  }

  @Test func xrgb8888ReordersAndForcesAlpha() {
    // LE memory for 0xXXRRGGBB is [BB, GG, RR, XX] — already BGRA order, alpha forced.
    #expect(bgra([0x10, 0x20, 0x30, 0x00], .xrgb8888) == [0x10, 0x20, 0x30, 255])
  }

  @Test func honorsPitchPadding() throws {
    // 2x2 RGB565, pitch 8 (4 bytes data + 4 padding per row).
    let bytes: [UInt8] = [
      0x00, 0xF8, 0xE0, 0x07, 0xAA, 0xBB, 0xCC, 0xDD,
      0x1F, 0x00, 0x00, 0xF8, 0xAA, 0xBB, 0xCC, 0xDD,
    ]
    let out = try #require(bgra(bytes, .rgb565, width: 2, height: 2, pitch: 8))
    #expect(out.count == 2 * 2 * 4)
    #expect(Array(out[0..<8]) == [0, 0, 255, 255, 0, 255, 0, 255])
    #expect(Array(out[8..<16]) == [255, 0, 0, 255, 0, 0, 255, 255])
  }

  // MARK: - Geometry a core reported and this process has to trust

  @Test func refusesGeometryWiderThanItsOwnPitch() {
    // The only place core-reported (width, height, pitch) becomes raw
    // pointer arithmetic in the app process: a width that overruns the
    // pitch must not read past the buffer.
    #expect(
      PixelConverter.toBGRA8(
        bytes: [UInt8](repeating: 0, count: 8), width: 4, height: 1, pitch: 4, format: .rgb565)
        == nil)
  }

  @Test func refusesBufferShorterThanPitchTimesHeight() {
    #expect(
      PixelConverter.toBGRA8(
        bytes: [UInt8](repeating: 0, count: 8), width: 2, height: 4, pitch: 4, format: .rgb565)
        == nil)
  }

  @Test func refusesZeroDimensions() {
    #expect(
      PixelConverter.toBGRA8(bytes: [], width: 0, height: 1, pitch: 0, format: .rgb565) == nil)
    #expect(
      PixelConverter.toBGRA8(bytes: [], width: 1, height: 0, pitch: 2, format: .rgb565) == nil)
  }
}
