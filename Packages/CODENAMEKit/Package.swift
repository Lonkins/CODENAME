// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CODENAMEKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "CODENAMEKit", targets: ["CODENAMEKit"])
  ],
  targets: [
    .target(name: "CODENAMEKit"),
    .testTarget(name: "CODENAMEKitTests", dependencies: ["CODENAMEKit"]),
  ]
)
