import Testing

@testable import CODENAMEKit

@Suite struct IntegerScalerTests {
  @Test func integerScaleCentersLargestFit() {
    let rect = IntegerScaler.destinationRect(
      contentWidth: 320, contentHeight: 240, aspectRatio: 4.0 / 3.0,
      drawableWidth: 1920, drawableHeight: 1080, integerOnly: true)
    // k = min(1920/320, 1080/240) = min(6, 4) = 4 → 1280x960 centered.
    #expect(rect == IntegerScaler.Rect(x: 320, y: 60, width: 1280, height: 960))
  }

  @Test func integerScaleNeverBelowOne() {
    let rect = IntegerScaler.destinationRect(
      contentWidth: 320, contentHeight: 240, aspectRatio: 4.0 / 3.0,
      drawableWidth: 200, drawableHeight: 100, integerOnly: true)
    #expect(rect.width == 320)
    #expect(rect.height == 240)
  }

  @Test func aspectFitFillsHeightForWideDrawable() {
    let rect = IntegerScaler.destinationRect(
      contentWidth: 256, contentHeight: 224, aspectRatio: 4.0 / 3.0,
      drawableWidth: 1920, drawableHeight: 1080, integerOnly: false)
    // 4:3 into 16:9 → 1440x1080 centered horizontally.
    #expect(rect == IntegerScaler.Rect(x: 240, y: 0, width: 1440, height: 1080))
  }

  @Test func aspectFitFillsWidthForTallDrawable() {
    let rect = IntegerScaler.destinationRect(
      contentWidth: 320, contentHeight: 240, aspectRatio: 4.0 / 3.0,
      drawableWidth: 800, drawableHeight: 1000, integerOnly: false)
    #expect(rect == IntegerScaler.Rect(x: 0, y: 200, width: 800, height: 600))
  }

  @Test func exactFitHasNoBorders() {
    let rect = IntegerScaler.destinationRect(
      contentWidth: 320, contentHeight: 240, aspectRatio: 4.0 / 3.0,
      drawableWidth: 640, drawableHeight: 480, integerOnly: true)
    #expect(rect == IntegerScaler.Rect(x: 0, y: 0, width: 640, height: 480))
  }
}
