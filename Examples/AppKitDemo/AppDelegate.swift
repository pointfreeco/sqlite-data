import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowControllers: [DemoWindowController] = []

  public func applicationWillFinishLaunching(_ notification: Notification) {
    let appMenu = NSMenuItem()
    appMenu.submenu = NSMenu()
    appMenu.submenu?.items = [
      NSMenuItem(
        title: "New Window",
        action: #selector(AppDelegate.newDemoWindow),
        keyEquivalent: "n"
      ),
      NSMenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "w"
      ),
      NSMenuItem(
        title: "Quit",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      ),
    ]
    let mainMenu = NSMenu()
    mainMenu.items = [appMenu]
    NSApplication.shared.mainMenu = mainMenu
  }
  public func applicationDidFinishLaunching(_ notification: Notification) {
    newDemoWindow()
  }
}

extension AppDelegate {
  @objc func newDemoWindow() {
    let windowController = DemoWindowController()
    windowController.showWindow(nil)
    windowControllers.append(windowController)
  }
  func removeWindowController(_ controller: DemoWindowController) {
    windowControllers.removeAll { $0 === controller }
  }
}

final class DemoWindowController: NSWindowController {
  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [
        .fullSizeContentView,
        .closable,
        .miniaturizable,
        .resizable,
        .titled,
      ],
      backing: .buffered,
      defer: false
    )

    window.titleVisibility = .visible
    window.toolbarStyle = .unified
    window.center()

    super.init(window: window)

    window.contentView = NSHostingView(rootView: Color.red)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  public func windowWillClose(_ notification: Notification) {
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.removeWindowController(self)
    }
  }
}
