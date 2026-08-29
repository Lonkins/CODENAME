// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CODENAMEKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "CODENAMEKit", targets: ["CODENAMEKit"]),
    .executable(name: "CODENAMEApp", targets: ["CODENAMEApp"]),
  ],
  targets: [
    .target(name: "CODENAMEKit"),
    .executableTarget(name: "CODENAMEApp"),
    .testTarget(name: "CODENAMEKitTests", dependencies: ["CODENAMEKit"]),
  ]
)
