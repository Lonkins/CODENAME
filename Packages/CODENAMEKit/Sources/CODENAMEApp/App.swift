import AppKit
import CODENAMEKit
import Sparkle

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var displayLoop: CoreDisplayLoop?
  private var inputController: InputController?
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "CODENAME"
    let gameView = GameView(frame: window.contentLayoutRect)
    gameView.autoresizingMask = [.width, .height]
    window.contentView = gameView
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()

    // The display link needs a non-zero drawableSize before it can vend drawables.
    gameView.layoutSubtreeIfNeeded()

    guard let coreURL = resolveCoreURL() else { return }
    let contentPath = ProcessInfo.processInfo.environment["CODENAME_CONTENT"]
    let refresh = Double(window.screen?.maximumFramesPerSecond ?? 60)
    let loop = CoreDisplayLoop(
      layer: gameView.metalLayer, coreURL: coreURL,
      contentPath: contentPath, displayRefresh: refresh)
    displayLoop = loop
    loop.start()

    let mapping = loadMapping(forCore: coreURL)
    let input = InputController(inputState: loop.inputState, mapping: mapping)
    input.start()
    inputController = input
  }

  /// Development override first (CODENAME_CORE), then bundled plug-ins.
  private func resolveCoreURL() -> URL? {
    if let override = ProcessInfo.processInfo.environment["CODENAME_CORE"] {
      return URL(fileURLWithPath: override)
    }
    guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
    let testCore = plugins.appendingPathComponent("libTestCore.dylib")
    return FileManager.default.fileExists(atPath: testCore.path) ? testCore : nil
  }

  private func loadMapping(forCore coreURL: URL) -> ButtonMapping {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let file = support[0]
      .appendingPathComponent("CODENAME/Mappings", isDirectory: true)
      .appendingPathComponent(coreURL.deletingPathExtension().lastPathComponent + ".json")
    return (try? ButtonMappingStore.load(from: file)) ?? .defaultMapping
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func makeMainMenu() -> NSMenu {
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "About CODENAME",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    let updateItem = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
    updateItem.target = updaterController
    appMenu.addItem(updateItem)
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit CODENAME",
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu
    let mainMenu = NSMenu()
    mainMenu.addItem(appMenuItem)
    return mainMenu
  }
}
