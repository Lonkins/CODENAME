import CLibretro

/// The three software pixel formats Phase 1 supports (ADR 0001; HW render is out of scope).
public enum LibretroPixelFormat: Sendable, Hashable {
  case zeroRGB1555
  case rgb565
  case xrgb8888

  public init?(_ format: retro_pixel_format) {
    switch format {
    case RETRO_PIXEL_FORMAT_0RGB1555: self = .zeroRGB1555
    case RETRO_PIXEL_FORMAT_RGB565: self = .rgb565
    case RETRO_PIXEL_FORMAT_XRGB8888: self = .xrgb8888
    default: return nil
    }
  }

  public var bytesPerPixel: Int {
    switch self {
    case .zeroRGB1555, .rgb565: 2
    case .xrgb8888: 4
    }
  }
}

/// Swift value mirror of `retro_system_av_info` — no C pointers escape the session layer.
public struct CoreAVInfo: Sendable, Hashable {
  public struct Size: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
      self.width = width
      self.height = height
    }
  }

  public let baseSize: Size
  public let maxSize: Size
  public let aspectRatio: Double
  public let framesPerSecond: Double
  public let audioSampleRate: Double

  public init(_ info: retro_system_av_info) {
    baseSize = Size(width: Int(info.geometry.base_width), height: Int(info.geometry.base_height))
    maxSize = Size(width: Int(info.geometry.max_width), height: Int(info.geometry.max_height))
    // Cores signal "derive from geometry" with aspect_ratio <= 0.
    let reported = Double(info.geometry.aspect_ratio)
    aspectRatio =
      reported > 0 ? reported : Double(info.geometry.base_width) / Double(info.geometry.base_height)
    framesPerSecond = info.timing.fps
    audioSampleRate = info.timing.sample_rate
  }
}
