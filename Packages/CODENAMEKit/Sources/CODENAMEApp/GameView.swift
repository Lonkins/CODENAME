import AppKit
import QuartzCore

/// The game surface: a CAMetalLayer-backed view. Rendering happens on the
/// core thread via CoreDisplayLoop; this view only owns the layer.
final class GameView: NSView {
  override var wantsUpdateLayer: Bool { true }

  var metalLayer: CAMetalLayer {
    // ponytail: force-cast safe — makeBackingLayer is the only layer source.
    layer as? CAMetalLayer ?? CAMetalLayer()
  }

  override func makeBackingLayer() -> CALayer {
    let layer = CAMetalLayer()
    layer.device = MTLCreateSystemDefaultDevice()
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = false
    return layer
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  override func layout() {
    super.layout()
    let scale = window?.backingScaleFactor ?? 2
    metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("not used")
  }
}
