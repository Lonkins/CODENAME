/// Failures on the path from a core file to a loaded, verified library.
public enum LoadError: Error, Equatable, Sendable {
  case outsideAllowedDirectory(String)
  case untrustedSignature(String)
  case notALoadableImage(String)
  case libraryOpenFailed(String)
  case missingSymbol(String)
  case unsupportedAPIVersion(UInt32)
}
