import AppKit
import CODENAMEKit
import Sparkle
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === recentsMenu { rebuildRecentsMenu() }
  }

  private var libraryWindow: NSWindow?
  private var settingsWindow: NSWindow?
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
    rescanAllSources()

    // Development/conformance auto-start path (ADR 0005 §5.7).
    if let core = ProcessInfo.processInfo.environment["CODENAME_CORE"] {
      startGame(
        coreURL: URL(fileURLWithPath: core),
        contentPath: ProcessInfo.processInfo.environment["CODENAME_CONTENT"])
    } else if let bundled = bundledTestCoreURL() {
      startGame(coreURL: bundled, contentPath: nil)
    }

    // Dev-only: launchd-hosted XPC service smoke (ADR 0006 step B).
    if ProcessInfo.processInfo.environment["CODENAME_XPC_SMOKE"] != nil {
      let connection = NSXPCConnection(serviceName: "dev.CODENAME.CoreHost")
      connection.remoteObjectInterface = CoreHostWire.interface()
      connection.resume()
      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        NSLog("xpc smoke failed: \(error.localizedDescription)")
      }
      (proxy as? CoreHostProtocol)?.handshake(version: CoreHostWire.version) { version in
        NSLog("xpc smoke: helper version %d", version)
      }
    }

    // Dev-only: headless fullscreen proof — toggle, then log geometry.
    if ProcessInfo.processInfo.environment["CODENAME_FULLSCREEN_TEST"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.gameWindow?.toggleFullScreen(nil)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let window = self?.gameWindow, let view = window.contentView as? GameView else {
          return
        }
        NSLog(
          "fullscreen test: frame %.0fx%.0f drawable %.0fx%.0f styleMask fullScreen=%d",
          window.frame.width, window.frame.height,
          view.metalLayer.drawableSize.width, view.metalLayer.drawableSize.height,
          window.styleMask.contains(.fullScreen) ? 1 : 0)
      }
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

  // Boundary hygiene (ADR 0001 amendment): cartridge content has hard size
  // maxima; refuse absurd files before handing bytes to a core.
  private static let maxContentBytes = 64 * 1024 * 1024

  private func openContent(at url: URL) {
    let size =
      (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    if let size, size > Self.maxContentBytes {
      let alert = NSAlert()
      alert.messageText = "File is too large to be cartridge content"
      alert.runModal()
      return
    }
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

  private var globalDisplaySettings: DisplaySettings {
    DisplaySettings(
      integerScale: UserDefaults.standard.object(forKey: "integerScale") as? Bool ?? true)
  }

  func startGame(
    coreURL: URL, contentPath: String?, contentAccess: ScopedAccess? = nil,
    displayOverrides: DisplaySettings? = nil
  ) {
    stopGame()
    self.contentAccess = contentAccess
    let resolved = DisplaySettings.resolve(
      global: globalDisplaySettings, override: displayOverrides)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = coreURL.deletingPathExtension().lastPathComponent
    window.collectionBehavior = [.fullScreenPrimary]
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
      contentPath: contentPath, displayRefresh: refresh,
      displaySettings: LiveDisplaySettings(resolved))
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
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "CODENAME"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: LibraryView(
        model: libraryModel,
        artwork: ArtworkStore(),
        onPlay: { [weak self] entry in self?.play(entry: entry) },
        onAddFolder: { [weak self] in self?.addFolderAction(nil) },
        onOpenFile: { [weak self] in self?.openGameAction(nil) },
        onImportArtwork: { [weak self] in self?.importArtworkAction(nil) }))
    window.center()
    window.makeKeyAndOrderFront(nil)
    libraryWindow = window
  }

  @objc private func addFolderAction(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      guard let bookmark = try? Bookmark.create(for: url) else { return }
      let source = self.libraryModel.addSource(bookmark: bookmark, name: url.lastPathComponent)
      self.rescan(source: source, at: url)
    }
  }

  @objc private func addCoreAction(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose a libretro core (.dylib)"
    panel.begin { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      guard url.pathExtension == "dylib" else { return }
      let plugins = Bundle.main.builtInPlugInsURL ?? URL(fileURLWithPath: "/nonexistent")
      let origin = CoreRouting.origin(of: url, bundledPlugInsDirectory: plugins)
      guard CoreRouting.requiresHelper(origin) else {
        self.alert("This core is already bundled with the app.")
        return
      }
      self.probeUserCore(at: url)
    }
  }

  private var probeConnection: NSXPCConnection?
  private var probeAccess: ScopedAccess?

  /// ADR 0001: unauthenticated cores never load in this process — the
  /// helper alone dlopens them.
  private func probeUserCore(at url: URL) {
    probeAccess = ScopedAccess(url: url)
    let connection = NSXPCConnection(serviceName: "dev.CODENAME.CoreHost")
    connection.remoteObjectInterface = CoreHostWire.interface()
    connection.resume()
    probeConnection = connection
    let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
      DispatchQueue.main.async {
        self?.finishProbe(
          message: "This build can’t run user-supplied cores: the isolation helper is unavailable."
        )
      }
    }
    (proxy as? CoreHostProtocol)?.probeCore(path: url.path) { [weak self] ok, name in
      DispatchQueue.main.async {
        let message =
          ok
          ? "“\(name)” verified in the isolated helper. "
            + "Playing user-supplied cores through the helper arrives in a future update."
          : "The isolation helper could not load this file as a libretro core."
        self?.finishProbe(message: message)
      }
    }
  }

  private func finishProbe(message: String) {
    probeConnection?.invalidate()
    probeConnection = nil
    probeAccess = nil
    alert(message)
  }

  private func alert(_ message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.runModal()
  }

  @objc private func importArtworkAction(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a folder of images named after your games"
    panel.begin { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      let access = ScopedAccess(url: url)
      let imported = ArtworkStore().importMatching(
        folder: url, entries: self.libraryModel.library.entries)
      _ = access
      self.libraryModel.noteArtworkChanged()
      let alert = NSAlert()
      alert.messageText = "Imported artwork for \(imported) game\(imported == 1 ? "" : "s")"
      alert.runModal()
    }
  }

  private func rescanAllSources() {
    for source in libraryModel.library.sources {
      guard let resolved = try? Bookmark.resolve(source.bookmark) else { continue }
      rescan(source: source, at: resolved.url)
    }
  }

  private func rescan(source: LibrarySource, at url: URL) {
    let access = ScopedAccess(url: url)
    let games = LibraryScanner.scan(root: url, extensions: Set(catalog.allExtensions))
    libraryModel.applyScan(sourceID: source.id, games: games) { [catalog] ext in
      catalog.core(forExtension: ext)?.url.deletingPathExtension().lastPathComponent
    }
    _ = access  // scan-scoped access
  }

  private func play(entry: GameEntry) {
    if let sourceID = entry.sourceID {
      guard let source = libraryModel.library.sources.first(where: { $0.id == sourceID }),
        let resolved = try? Bookmark.resolve(source.bookmark)
      else { return }
      let contentURL = resolved.url.appendingPathComponent(entry.relativePath)
      libraryModel.recordPlay(
        path: entry.relativePath, displayName: entry.displayName,
        coreID: entry.coreID, bookmark: nil)
      startGameRouted(
        contentURL: contentURL, coreID: entry.coreID,
        contentAccess: ScopedAccess(url: resolved.url),
        displayOverrides: entry.displayOverrides)
    } else {
      let recentsStyle = NSMenuItem()
      recentsStyle.representedObject = entry
      openRecentAction(recentsStyle)
    }
  }

  private func startGameRouted(
    contentURL: URL, coreID: String, contentAccess: ScopedAccess,
    displayOverrides: DisplaySettings? = nil
  ) {
    guard
      let core = catalog.entries.first(where: {
        $0.url.deletingPathExtension().lastPathComponent == coreID
      }) ?? catalog.core(forExtension: contentURL.pathExtension)
    else { return }
    startGame(
      coreURL: core.url, contentPath: contentURL.path, contentAccess: contentAccess,
      displayOverrides: displayOverrides)
  }

  private var remapWindow: NSWindow?

  @objc private func showRemapAction(_ sender: Any?) {
    if let remapWindow {
      remapWindow.makeKeyAndOrderFront(nil)
      return
    }
    let names = catalog.entries.map { $0.url.deletingPathExtension().lastPathComponent }
    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Controller Mapping"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: RemapView(
        coreNames: names,
        load: { [weak self] core in self?.mappingOnDisk(forCoreNamed: core) ?? .defaultMapping },
        save: { [weak self] core, mapping in self?.saveMapping(mapping, forCoreNamed: core) }))
    window.center()
    window.makeKeyAndOrderFront(nil)
    remapWindow = window
  }

  private func mappingURL(forCoreNamed core: String) -> URL {
    AppPaths.mappings.appendingPathComponent(core + ".json")
  }

  private func mappingOnDisk(forCoreNamed core: String) -> ButtonMapping {
    (try? ButtonMappingStore.load(from: mappingURL(forCoreNamed: core))) ?? .defaultMapping
  }

  private func saveMapping(_ mapping: ButtonMapping, forCoreNamed core: String) {
    AppPaths.ensureExists()
    try? ButtonMappingStore.save(mapping, to: mappingURL(forCoreNamed: core))
  }

  @objc private func showSettingsAction(_ sender: Any?) {
    if let settingsWindow {
      settingsWindow.makeKeyAndOrderFront(nil)
      return
    }
    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Settings"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: SettingsView(
        licences: loadCoreLicences(),
        onIntegerScaleChange: { [weak self] value in
          self?.displayLoop?.displaySettings.integerScale = value
        }))
    window.center()
    window.makeKeyAndOrderFront(nil)
    settingsWindow = window
  }

  private func loadCoreLicences() -> [(name: String, text: String)] {
    guard let resources = Bundle.main.resourceURL else { return [] }
    let directory = resources.appendingPathComponent("CoreLicences", isDirectory: true)
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      return (name: url.deletingPathExtension().lastPathComponent, text: text)
    }
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
    let settingsItem = NSMenuItem(
      title: "Settings…", action: #selector(showSettingsAction(_:)), keyEquivalent: ",")
    settingsItem.target = self
    appMenu.addItem(settingsItem)
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
    let addFolderItem = NSMenuItem(
      title: "Add Folder…", action: #selector(addFolderAction(_:)), keyEquivalent: "O")
    addFolderItem.target = self
    fileMenu.addItem(addFolderItem)
    let addCoreItem = NSMenuItem(
      title: "Add Core…", action: #selector(addCoreAction(_:)), keyEquivalent: "")
    addCoreItem.target = self
    fileMenu.addItem(addCoreItem)

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
    let remapItem = NSMenuItem(
      title: "Controller Mapping…", action: #selector(showRemapAction(_:)), keyEquivalent: "")
    remapItem.target = self
    gameMenu.addItem(remapItem)
    gameMenu.addItem(.separator())
    let fullScreenItem = NSMenuItem(
      title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)),
      keyEquivalent: "f")
    fullScreenItem.keyEquivalentModifierMask = [.control, .command]
    gameMenu.addItem(fullScreenItem)
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
