/// Placement math for the presenter (north star: nearest-neighbour with a
/// configurable integer-scale mode).
public enum IntegerScaler {
  public struct Rect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }

  /// Integer mode scales raw pixel dimensions (sharpness first, aspect
  /// uncorrected); fit mode aspect-corrects to the largest contained rect.
  public static func destinationRect(
    contentWidth: Int, contentHeight: Int, aspectRatio: Double,
    drawableWidth: Int, drawableHeight: Int, integerOnly: Bool
  ) -> Rect {
    let width: Int
    let height: Int
    if integerOnly {
      let scale = max(1, min(drawableWidth / contentWidth, drawableHeight / contentHeight))
      width = contentWidth * scale
      height = contentHeight * scale
    } else {
      let drawableAspect = Double(drawableWidth) / Double(drawableHeight)
      if drawableAspect > aspectRatio {
        height = drawableHeight
        width = Int((Double(drawableHeight) * aspectRatio).rounded())
      } else {
        width = drawableWidth
        height = Int((Double(drawableWidth) / aspectRatio).rounded())
      }
    }
    return Rect(
      x: (drawableWidth - width) / 2, y: (drawableHeight - height) / 2,
      width: width, height: height)
  }
}
