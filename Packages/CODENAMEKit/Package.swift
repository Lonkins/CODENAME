// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CODENAMEKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "CODENAMEKit", targets: ["CODENAMEKit"]),
    .executable(name: "CODENAMEApp", targets: ["CODENAMEApp"]),
    .library(name: "TestCore", type: .dynamic, targets: ["TestCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
  ],
  targets: [
    .target(name: "CLibretro"),
    .target(name: "TestCore", dependencies: ["CLibretro"], publicHeadersPath: ""),
    .target(name: "CODENAMEKit", dependencies: ["CLibretro"]),
    .executableTarget(
      name: "CODENAMEApp",
      dependencies: [.product(name: "Sparkle", package: "Sparkle")],
      linkerSettings: [
        // Sparkle.framework is embedded by Scripts/make-app.sh.
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]
    ),
    .testTarget(name: "CODENAMEKitTests", dependencies: ["CODENAMEKit"]),
  ]
)
