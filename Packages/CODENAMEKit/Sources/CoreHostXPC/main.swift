import CODENAMEKit
import Foundation

// The bundled XPC service entry point (ADR 0006 step B): accepts connections
// and serves the wire protocol. Core hosting arrives in step C.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
  private let service = CoreHostService()

  func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = CoreHostWire.interface()
    newConnection.exportedObject = service
    newConnection.resume()
    return true
  }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
