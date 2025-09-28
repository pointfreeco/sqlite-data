import AppKit

final class SidebarViewController: NSViewController {
  private var outlineView: NSOutlineView!
  private var scrollView: NSScrollView!
  private let dataSource = OutlineDataSource()

  init() {
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    self.view = NSView()

    scrollView = NSScrollView()
    scrollView.autoresizingMask = [.width, .height]
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true

    outlineView = NSOutlineView()
    outlineView.autoresizingMask = [.width, .height]

    outlineView.dataSource = dataSource
    outlineView.delegate = self

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
    column.title = "Schema"
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column

    //outlineView.headerView = nil

    scrollView.documentView = outlineView
    self.view.addSubview(scrollView)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    outlineView.reloadData()
  }
}

extension SidebarViewController: NSOutlineViewDelegate {
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let item = item as? OutlineDataSource.OutlineItem else { return nil }

    let cellView = NSTableCellView()

    let textField = NSTextField(labelWithString: item.title)
    textField.translatesAutoresizingMaskIntoConstraints = false

    cellView.addSubview(textField)
    cellView.textField = textField

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 5),
      textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
      textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
    ])

    return cellView
  }
}

final class OutlineDataSource: NSObject, NSOutlineViewDataSource {

  struct OutlineItem {
    let title: String
    let children: [OutlineItem]?
  }

  // Sample data
  private let outlineData: [OutlineItem] = [
    OutlineItem(
      title: "Tables",
      children: [
        OutlineItem(title: "Users", children: nil),
        OutlineItem(title: "Posts", children: nil),
        OutlineItem(title: "Comments", children: nil),
      ]
    ),
    OutlineItem(
      title: "Views",
      children: [
        OutlineItem(title: "User Posts", children: nil),
        OutlineItem(title: "Popular Posts", children: nil),
      ]
    ),
    OutlineItem(title: "Indexes", children: nil),
  ]

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if let item = item as? OutlineItem {
      return item.children?.count ?? 0
    }
    return outlineData.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if let item = item as? OutlineItem {
      return item.children![index]
    }
    return outlineData[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if let item = item as? OutlineItem {
      return item.children != nil && !item.children!.isEmpty
    }
    return false
  }
}
