import AppKit
import SQLiteData

final class RootViewController: NSSplitViewController {
  init() {
    super.init(nibName: nil, bundle: nil)

    let sidebarViewController = SidebarViewController()
    let detailViewController = DetailViewController()

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    let detailItem = NSSplitViewItem(viewController: detailViewController)

    sidebarItem.canCollapse = false
    sidebarItem.minimumThickness = 250
    sidebarItem.maximumThickness = 350

    self.addSplitViewItem(sidebarItem)
    self.addSplitViewItem(detailItem)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
