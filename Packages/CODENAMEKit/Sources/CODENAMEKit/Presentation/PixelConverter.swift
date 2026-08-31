/// Converts core framebuffers to tightly packed BGRA8 (Metal `.bgra8Unorm`).
public enum PixelConverter {
  /// `nil` when the reported geometry does not fit the buffer it describes.
  /// Cores report width, height and pitch themselves, and this is the one
  /// place those numbers become raw pointer arithmetic in the app process
  /// — where `UnsafeBufferPointer` subscripts are unchecked in release.
  public static func toBGRA8(
    bytes: [UInt8], width: Int, height: Int, pitch: Int, format: LibretroPixelFormat
  ) -> [UInt8]? {
    guard width > 0, height > 0, pitch >= width * format.bytesPerPixel,
      bytes.count >= pitch * height
    else { return nil }
    var out = [UInt8](repeating: 0, count: width * height * 4)

    bytes.withUnsafeBufferPointer { source in
      out.withUnsafeMutableBufferPointer { destination in
        for row in 0..<height {
          let rowStart = row * pitch
          var write = row * width * 4
          switch format {
          case .xrgb8888:
            // LE memory for 0xXXRRGGBB is already [B, G, R, X]; force alpha.
            for column in 0..<width {
              let read = rowStart + column * 4
              destination[write] = source[read]
              destination[write + 1] = source[read + 1]
              destination[write + 2] = source[read + 2]
              destination[write + 3] = 255
              write += 4
            }
          case .rgb565:
            for column in 0..<width {
              let read = rowStart + column * 2
              let value = UInt16(source[read]) | (UInt16(source[read + 1]) << 8)
              let red = UInt8((value >> 11) & 0x1F)
              let green = UInt8((value >> 5) & 0x3F)
              let blue = UInt8(value & 0x1F)
              destination[write] = (blue << 3) | (blue >> 2)
              destination[write + 1] = (green << 2) | (green >> 4)
              destination[write + 2] = (red << 3) | (red >> 2)
              destination[write + 3] = 255
              write += 4
            }
          case .zeroRGB1555:
            for column in 0..<width {
              let read = rowStart + column * 2
              let value = UInt16(source[read]) | (UInt16(source[read + 1]) << 8)
              let red = UInt8((value >> 10) & 0x1F)
              let green = UInt8((value >> 5) & 0x1F)
              let blue = UInt8(value & 0x1F)
              destination[write] = (blue << 3) | (blue >> 2)
              destination[write + 1] = (green << 3) | (green >> 2)
              destination[write + 2] = (red << 3) | (red >> 2)
              destination[write + 3] = 255
              write += 4
            }
          }
        }
      }
    }
    return out
  }
}
