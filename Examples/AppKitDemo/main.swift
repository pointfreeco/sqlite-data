import AppKit

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.regular)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
