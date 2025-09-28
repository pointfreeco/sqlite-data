import AppKit
import AppKitNavigation
import SQLiteData

final class SidebarViewController: NSViewController {
  private let model: AppModel
  private var outlineView: NSOutlineView!
  private var scrollView: NSScrollView!
  private var outlineItems: [OutlineItem] = []
  @FetchAll private var rows: [Row]

  @Selection
  struct Row {
    let remindersList: RemindersList
    @Column(as: [Reminder].JSONRepresentation.self)
    let reminders: [Reminder]
  }

  init(model: AppModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)

    $rows = FetchAll(
      RemindersList.all
        .group(by: \.id)
        .order(by: \.title)
        .join(Reminder.all) { $0.id.eq($1.remindersListID) }
        .select {
          Row.Columns(
            remindersList: $0,
            reminders: $1.jsonGroupArray() // FIXME: order reminders
          )
        }
    )

    observe { [weak self] in
      guard let self else { return }
      self.outlineItems = rows.map { row in
        OutlineItem.remindersList(
          row.remindersList,
          row.reminders
        )
      }
      self.outlineView?.reloadData()
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

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("RemindersColumn"))
    column.title = "Reminders"
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column

    outlineView.headerView = nil

    scrollView.documentView = outlineView
    self.view.addSubview(scrollView)
  }
}

private enum OutlineItem {
  case reminder(Reminder)
  case remindersList(RemindersList, [Reminder])
}

extension SidebarViewController: NSOutlineViewDelegate {
  func outlineView(
    _ outlineView: NSOutlineView,
    viewFor tableColumn: NSTableColumn?,
    item: Any
  ) -> NSView? {
    guard let item = item as? OutlineItem else { return nil }

    let cellView = NSTableCellView()

    switch item {
    case .reminder(let reminder):
      let textField = NSTextField(labelWithString: reminder.title)
      textField.translatesAutoresizingMaskIntoConstraints = false
      cellView.textField = textField

      if reminder.isCompleted {
        let checkmark = NSImageView(
          image: NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Completed"
          )!
        )

        let stack = NSStackView(views: [checkmark, textField])
        cellView.addSubview(stack)

        NSLayoutConstraint.activate([
          stack.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
          stack.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
          stack.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])
      } else {
        cellView.addSubview(textField)

        NSLayoutConstraint.activate([
          textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
          textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
          textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])
      }

    case .remindersList(let remindersList, _):

      let textField = NSTextField(labelWithString: remindersList.title)
      textField.translatesAutoresizingMaskIntoConstraints = false
      cellView.textField = textField

      cellView.addSubview(textField)

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 3),
        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])
    }

    return cellView
  }
  func outlineViewSelectionDidChange(_ notification: Notification) {
    let row = outlineView.selectedRow
    guard
      row >= 0,
      let item = outlineView.item(atRow: row) as? OutlineItem
    else {
      return
    }
    switch item {
    case .reminder(let reminder):
      model.reminderSelectedInOutline(reminder)
    case .remindersList(let remindersList, _):
      model.remindersListSelectedInOutline(remindersList)
    }
  }
}

extension SidebarViewController: NSOutlineViewDataSource {
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    switch item as? OutlineItem {
    case .reminder: outlineItems[index]
    case .remindersList(_, let reminders): OutlineItem.reminder(reminders[index])
    case .none: outlineItems[index]
    }
  }
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    switch item as? OutlineItem {
    case .reminder: 0
    case .remindersList(_, let reminders): reminders.count
    case .none: outlineItems.count
    }
  }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    switch item as? OutlineItem {
    case .reminder: false
    case .remindersList(_, let reminders): !reminders.isEmpty
    case .none: false
    }
  }
}

#Preview {
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
  }
  SidebarViewController(
    model: AppModel()
  )
}
