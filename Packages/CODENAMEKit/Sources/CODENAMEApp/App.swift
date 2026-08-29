import AppKit
import CODENAMEKit
import Sparkle

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var libraryWindow: NSWindow?
  private var gameWindow: NSWindow?
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
    showLibraryWindow()
    NSApp.activate()

    // Development/conformance auto-start path (ADR 0005 §5.7).
    if let core = ProcessInfo.processInfo.environment["CODENAME_CORE"] {
      startGame(
        coreURL: URL(fileURLWithPath: core),
        contentPath: ProcessInfo.processInfo.environment["CODENAME_CONTENT"])
    } else if let bundled = bundledTestCoreURL() {
      startGame(coreURL: bundled, contentPath: nil)
    }

    // Dev-only: exercise the stop path without UI automation.
    if let seconds = ProcessInfo.processInfo.environment["CODENAME_AUTOSTOP_SECONDS"]
      .flatMap(Double.init)
    {
      DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
        self?.stopGame()
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows { showLibraryWindow() }
    return true
  }

  // MARK: - Session lifecycle (ADR 0005: window existence == session existence)

  func startGame(coreURL: URL, contentPath: String?) {
    stopGame()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = coreURL.deletingPathExtension().lastPathComponent
    let gameView = GameView(frame: window.contentLayoutRect)
    gameView.autoresizingMask = [.width, .height]
    window.contentView = gameView
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    gameView.layoutSubtreeIfNeeded()

    let refresh = Double(window.screen?.maximumFramesPerSecond ?? 60)
    let loop = CoreDisplayLoop(
      layer: gameView.metalLayer, coreURL: coreURL,
      contentPath: contentPath, displayRefresh: refresh)
    let input = InputController(inputState: loop.inputState, mapping: loadMapping(forCore: coreURL))
    input.start()

    gameWindow = window
    displayLoop = loop
    inputController = input
    loop.start()
  }

  func stopGame() {
    displayLoop?.stop()
    displayLoop = nil
    inputController = nil
    if let window = gameWindow {
      window.delegate = nil
      window.close()
      gameWindow = nil
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === gameWindow else { return }
    gameWindow?.delegate = nil
    gameWindow = nil
    stopGame()
  }

  @objc private func stopGameAction(_ sender: Any?) {
    stopGame()
  }

  // MARK: - Windows and menu

  private func showLibraryWindow() {
    if let libraryWindow {
      libraryWindow.makeKeyAndOrderFront(nil)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "CODENAME"
    window.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: "Open a Genesis or SNES game\nFile → Open…")
    label.alignment = .center
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 16)
    label.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView()
    content.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    window.contentView = content
    window.center()
    window.makeKeyAndOrderFront(nil)
    libraryWindow = window
  }

  private func bundledTestCoreURL() -> URL? {
    guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
    let testCore = plugins.appendingPathComponent("libTestCore.dylib")
    return FileManager.default.fileExists(atPath: testCore.path) ? testCore : nil
  }

  private func loadMapping(forCore coreURL: URL) -> ButtonMapping {
    let file = AppPaths.mappings
      .appendingPathComponent(coreURL.deletingPathExtension().lastPathComponent + ".json")
    return (try? ButtonMappingStore.load(from: file)) ?? .defaultMapping
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

    let gameMenu = NSMenu(title: "Game")
    let stopItem = NSMenuItem(
      title: "Stop", action: #selector(stopGameAction(_:)), keyEquivalent: "w")
    stopItem.target = self
    gameMenu.addItem(stopItem)

    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu
    let gameMenuItem = NSMenuItem()
    gameMenuItem.submenu = gameMenu
    let mainMenu = NSMenu()
    mainMenu.addItem(appMenuItem)
    mainMenu.addItem(gameMenuItem)
    return mainMenu
  }
}
