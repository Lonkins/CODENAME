import CLibretro
import Testing

@testable import CODENAMEKit

@Suite struct LibretroPixelFormatTests {
  @Test func mapsKnownFormats() {
    #expect(LibretroPixelFormat(RETRO_PIXEL_FORMAT_0RGB1555) == .zeroRGB1555)
    #expect(LibretroPixelFormat(RETRO_PIXEL_FORMAT_XRGB8888) == .xrgb8888)
    #expect(LibretroPixelFormat(RETRO_PIXEL_FORMAT_RGB565) == .rgb565)
  }

  @Test func rejectsUnknown() {
    #expect(LibretroPixelFormat(RETRO_PIXEL_FORMAT_UNKNOWN) == nil)
    #expect(LibretroPixelFormat(retro_pixel_format(rawValue: 927)) == nil)
  }

  @Test func bytesPerPixel() {
    #expect(LibretroPixelFormat.zeroRGB1555.bytesPerPixel == 2)
    #expect(LibretroPixelFormat.rgb565.bytesPerPixel == 2)
    #expect(LibretroPixelFormat.xrgb8888.bytesPerPixel == 4)
  }
}

@Suite struct CoreAVInfoTests {
  private func sampleCInfo() -> retro_system_av_info {
    var info = retro_system_av_info()
    info.geometry.base_width = 256
    info.geometry.base_height = 224
    info.geometry.max_width = 512
    info.geometry.max_height = 448
    // 1.5 is exactly representable in Float, so the Double round-trip compares exactly.
    info.geometry.aspect_ratio = 1.5
    info.timing.fps = 60.0988
    info.timing.sample_rate = 32040.5
    return info
  }

  @Test func roundTripsFromC() {
    let av = CoreAVInfo(sampleCInfo())
    #expect(av.baseSize == CoreAVInfo.Size(width: 256, height: 224))
    #expect(av.maxSize == CoreAVInfo.Size(width: 512, height: 448))
    #expect(av.aspectRatio == 1.5)
    #expect(av.framesPerSecond == 60.0988)
    #expect(av.audioSampleRate == 32040.5)
  }

  @Test func derivesAspectFromGeometryWhenUnset() {
    var info = sampleCInfo()
    info.geometry.aspect_ratio = 0
    let av = CoreAVInfo(info)
    #expect(av.aspectRatio == 256.0 / 224.0)
  }
}
