import AppKit
import AppKitNavigation
import SQLiteData

final class SidebarViewController: NSViewController {
  private var outlineView: NSOutlineView!
  private var scrollView: NSScrollView!
  private var outlineItems: [OutlineItem] = []
  @FetchAll private var rows: [Row]

  @Selection
  struct Row {
    let remindersListTitle: String
    @Column(as: [String].JSONRepresentation.self)
    let reminderTitles: [String]
  }

  init() {
    super.init(nibName: nil, bundle: nil)

    $rows = FetchAll(
      RemindersList.all
        .group(by: \.id)
        .join(Reminder.all) { $0.id.eq($1.remindersListID) }
        .select {
          Row.Columns(
            remindersListTitle: $0.title,
            reminderTitles: $1.title.jsonGroupArray()
          )
        }
    )

    observe { [weak self] in
      guard let self else { return }
      self.outlineItems = rows.map { record in
        OutlineItem(
          title: record.remindersListTitle,
          children: record.reminderTitles.map {
            OutlineItem(title: $0, children: [])
          }
        )
      }
    }
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

    outlineView.dataSource = self
    outlineView.delegate = self

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
    column.title = "Schema"
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column

    outlineView.headerView = nil

    scrollView.documentView = outlineView
    self.view.addSubview(scrollView)
  }
}

fileprivate struct OutlineItem {
  let title: String
  let children: [OutlineItem]?
}

extension SidebarViewController: NSOutlineViewDelegate {
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let item = item as? OutlineItem else { return nil }

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

extension SidebarViewController: NSOutlineViewDataSource {

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if let item = item as? OutlineItem {
      return item.children?.count ?? 0
    }
    return outlineItems.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if let item = item as? OutlineItem {
      return item.children![index]
    }
    return outlineItems[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if let item = item as? OutlineItem {
      return item.children != nil && !item.children!.isEmpty
    }
    return false
  }
}
