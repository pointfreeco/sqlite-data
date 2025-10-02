import AppKit

final class RootViewController: NSSplitViewController {
  let model: AppModel
  init(model: AppModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)

    let sidebarViewController = SidebarViewController(model: model)
    let detailViewController = DetailViewController(model: model)

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
