import AppKit
import SQLiteData

final class RootViewController: NSSplitViewController {
  init() {
    super.init(nibName: nil, bundle: nil)

    let sidebarViewController = SidebarViewController()
    let contentViewController = ContentViewController()

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    let detailItem = NSSplitViewItem(viewController: contentViewController)

    sidebarItem.minimumThickness = 250
    sidebarItem.maximumThickness = 350

    self.addSplitViewItem(sidebarItem)
    self.addSplitViewItem(detailItem)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

final class ContentViewController: NSViewController {
  init() {
    super.init(nibName: nil, bundle: nil)
    self.view.wantsLayer = true
    self.view.layer?.backgroundColor = .white
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
