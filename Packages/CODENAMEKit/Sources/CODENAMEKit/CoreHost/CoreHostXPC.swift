import Foundation
import IOSurface

/// Wire protocol for the out-of-process core helper (ADR 0006). Deliberately
/// tiny: handshake + an IOSurface round trip prove the serialization
/// machinery; core hosting arrives with the helper's own environment.
@objc public protocol CoreHostProtocol {
  func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void)
  func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void)
}

public enum CoreHostWire {
  public static let version = 1

  public static func interface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: CoreHostProtocol.self)
    let allowed = NSSet(object: IOSurface.self) as? Set<AnyHashable> ?? []
    interface.setClasses(
      allowed,
      for: #selector(CoreHostProtocol.roundTripFrame(_:reply:)),
      argumentIndex: 0, ofReply: false)
    return interface
  }
}

/// Helper-side implementation. @unchecked Sendable: stateless; XPC invokes
/// on its own queue.
public final class CoreHostService: NSObject, CoreHostProtocol, @unchecked Sendable {
  public func handshake(version: Int, reply: @escaping @Sendable (Int) -> Void) {
    reply(CoreHostWire.version)
  }

  public func roundTripFrame(_ surface: IOSurface, reply: @escaping @Sendable (Int, Int) -> Void) {
    reply(IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
  }
}

/// Anonymous-listener loopback: the full NSXPCConnection serialization path
/// with no launchd involvement — CI-deterministic (ADR 0006 verification
/// strategy). @unchecked Sendable: connection/listener are internally
/// thread-safe; service is stateless.
public final class LoopbackCoreHost: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener: NSXPCListener
  private let connection: NSXPCConnection
  private let service = CoreHostService()

  override public init() {
    listener = NSXPCListener.anonymous()
    connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    super.init()
    listener.delegate = self
    listener.resume()
    connection.remoteObjectInterface = CoreHostWire.interface()
    connection.resume()
  }

  deinit {
    connection.invalidate()
    listener.invalidate()
  }

  public func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = CoreHostWire.interface()
    newConnection.exportedObject = service
    newConnection.resume()
    return true
  }

  public func proxy(errorHandler: @escaping @Sendable (any Error) -> Void) -> CoreHostProtocol? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? CoreHostProtocol
  }
}
