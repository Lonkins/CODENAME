import Metal

/// Blits a core frame into a render target with nearest-neighbour sampling.
/// Shader compiles from source at init (ADR 0002: no build-time Metal
/// toolchain; one shader, negligible startup cost — revisit if that grows).
public final class MetalPresenter {
  public enum RenderError: Error {
    case commandCreationFailed
    case textureCreationFailed
  }

  public let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var sourceTexture: MTLTexture?

  private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
      float4 position [[position]];
      float2 uv;
    };

    vertex VertexOut blit_vertex(uint vid [[vertex_id]]) {
      float2 positions[4] = {float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1)};
      float2 uvs[4] = {float2(0,1), float2(1,1), float2(0,0), float2(1,0)};
      VertexOut out;
      out.position = float4(positions[vid], 0, 1);
      out.uv = uvs[vid];
      return out;
    }

    fragment float4 blit_fragment(VertexOut in [[stage_in]],
                                  texture2d<float> source [[texture(0)]]) {
      constexpr sampler nearest(coord::normalized, filter::nearest);
      return source.sample(nearest, in.uv);
    }
    """

  public init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
      let vertexFunction = library.makeFunction(name: "blit_vertex"),
      let fragmentFunction = library.makeFunction(name: "blit_fragment")
    else { return nil }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
      return nil
    }

    self.device = device
    self.queue = queue
    self.pipeline = pipeline
  }

  public func render(
    frame: CoreSession.VideoFrame, into target: MTLTexture, destination: IntegerScaler.Rect,
    presenting drawable: (any MTLDrawable)? = nil
  ) throws {
    let bgra = PixelConverter.toBGRA8(
      bytes: frame.bytes, width: frame.width, height: frame.height,
      pitch: frame.pitch, format: frame.pixelFormat)

    let source = try sourceTexture(width: frame.width, height: frame.height)
    bgra.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      source.replace(
        region: MTLRegionMake2D(0, 0, frame.width, frame.height), mipmapLevel: 0,
        withBytes: base, bytesPerRow: frame.width * 4)
    }

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    pass.colorAttachments[0].storeAction = .store

    guard let commands = queue.makeCommandBuffer(),
      let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
    else { throw RenderError.commandCreationFailed }

    encoder.setRenderPipelineState(pipeline)
    encoder.setViewport(
      MTLViewport(
        originX: Double(destination.x), originY: Double(destination.y),
        width: Double(destination.width), height: Double(destination.height),
        znear: 0, zfar: 1))
    encoder.setFragmentTexture(source, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    // Canonical present: scheduled inside the command buffer, so drawables
    // recycle regardless of app activation state.
    if let drawable {
      commands.present(drawable)
    }
    commands.commit()
    commands.waitUntilCompleted()
  }

  private func sourceTexture(width: Int, height: Int) throws -> MTLTexture {
    if let existing = sourceTexture, existing.width == width, existing.height == height {
      return existing
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw RenderError.textureCreationFailed
    }
    sourceTexture = texture
    return texture
  }
}
