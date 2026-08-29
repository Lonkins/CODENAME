import AppKit
import CODENAMEKit
import Sparkle

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === recentsMenu { rebuildRecentsMenu() }
  }

  private var libraryWindow: NSWindow?
  private var gameWindow: NSWindow?
  private var displayLoop: CoreDisplayLoop?
  private var inputController: InputController?
  private var contentAccess: ScopedAccess?
  private let libraryModel = LibraryModel()
  private let recentsMenu = NSMenu(title: "Open Recent")
  private lazy var catalog = CoreCatalog(
    pluginsDirectory: Bundle.main.builtInPlugInsURL ?? URL(fileURLWithPath: "/nonexistent"))
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

  @objc private func openGameAction(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      self.openContent(at: url)
    }
  }

  private func openContent(at url: URL) {
    guard let entry = catalog.core(forExtension: url.pathExtension) else {
      let alert = NSAlert()
      alert.messageText = "No bundled core plays “.\(url.pathExtension)” files"
      alert.informativeText =
        "Supported types: \(catalog.allExtensions.map { ".\($0)" }.joined(separator: ", "))"
      alert.runModal()
      return
    }
    libraryModel.recordPlay(
      path: url.path,
      displayName: url.deletingPathExtension().lastPathComponent,
      coreID: entry.url.deletingPathExtension().lastPathComponent,
      bookmark: try? Bookmark.create(for: url))
    startGame(coreURL: entry.url, contentPath: url.path, contentAccess: ScopedAccess(url: url))
  }

  @objc private func openRecentAction(_ sender: NSMenuItem) {
    guard let entry = sender.representedObject as? GameEntry else { return }
    guard let bookmark = entry.bookmark,
      let resolved = try? Bookmark.resolve(bookmark),
      FileManager.default.fileExists(atPath: resolved.url.path)
    else {
      let alert = NSAlert()
      alert.messageText = "“\(entry.displayName)” can’t be found"
      alert.informativeText = "The file may have moved. Use File → Open… to locate it."
      alert.runModal()
      return
    }
    if resolved.isStale, let fresh = try? Bookmark.create(for: resolved.url) {
      libraryModel.recordPlay(
        path: entry.relativePath, displayName: entry.displayName,
        coreID: entry.coreID, bookmark: fresh)
    }
    openContent(at: resolved.url)
  }

  private func rebuildRecentsMenu() {
    recentsMenu.removeAllItems()
    let recents = libraryModel.recents(limit: 10)
    for entry in recents {
      let item = NSMenuItem(
        title: entry.displayName, action: #selector(openRecentAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = entry
      recentsMenu.addItem(item)
    }
    if recents.isEmpty {
      let empty = NSMenuItem(title: "No Recent Games", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      recentsMenu.addItem(empty)
    }
  }

  func startGame(coreURL: URL, contentPath: String?, contentAccess: ScopedAccess? = nil) {
    stopGame()
    self.contentAccess = contentAccess

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
    contentAccess = nil
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

  @objc private func saveStateAction(_ sender: NSMenuItem) {
    displayLoop?.requestSaveState(slot: sender.tag)
  }

  @objc private func loadStateAction(_ sender: NSMenuItem) {
    displayLoop?.requestLoadState(slot: sender.tag)
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

    let fileMenu = NSMenu(title: "File")
    let openItem = NSMenuItem(
      title: "Open…", action: #selector(openGameAction(_:)), keyEquivalent: "o")
    openItem.target = self
    fileMenu.addItem(openItem)
    let recentsItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recentsMenu.delegate = self
    recentsItem.submenu = recentsMenu
    fileMenu.addItem(recentsItem)

    let gameMenu = NSMenu(title: "Game")
    for slot in 1...3 {
      let save = NSMenuItem(
        title: "Save State — Slot \(slot)", action: #selector(saveStateAction(_:)),
        keyEquivalent: slot == 1 ? "s" : "")
      save.target = self
      save.tag = slot
      gameMenu.addItem(save)
    }
    gameMenu.addItem(.separator())
    for slot in 1...3 {
      let load = NSMenuItem(
        title: "Load State — Slot \(slot)", action: #selector(loadStateAction(_:)),
        keyEquivalent: slot == 1 ? "l" : "")
      load.target = self
      load.tag = slot
      gameMenu.addItem(load)
    }
    gameMenu.addItem(.separator())
    let stopItem = NSMenuItem(
      title: "Stop", action: #selector(stopGameAction(_:)), keyEquivalent: "w")
    stopItem.target = self
    gameMenu.addItem(stopItem)

    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu
    let fileMenuItem = NSMenuItem()
    fileMenuItem.submenu = fileMenu
    let gameMenuItem = NSMenuItem()
    gameMenuItem.submenu = gameMenu
    let mainMenu = NSMenu()
    mainMenu.addItem(appMenuItem)
    mainMenu.addItem(fileMenuItem)
    mainMenu.addItem(gameMenuItem)
    return mainMenu
  }
}
