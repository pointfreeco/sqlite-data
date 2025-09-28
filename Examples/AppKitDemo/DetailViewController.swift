import AppKit
import CasePaths
import SQLiteData
import SwiftUI

final class DetailViewController: NSViewController {
  let model: AppModel
  init(model: AppModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  override func loadView() {
    let hostingView = FullSizeHostingView(
      rootView: DetailView(model: model)
        .frame(
          minWidth: 600,
          maxWidth: .infinity,
          minHeight: 500,
          maxHeight: .infinity
        )
    )
    self.view = hostingView
  }
  class FullSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
      return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
  }
}

private struct DetailView: View {
  let model: AppModel
  var body: some View {
    switch model.destination {
    case .remindersList(let model):
      RemindersListDetailView(model: model)
    case .reminder(let model):
      ReminderDetailView(model: model)
    case .none:
      ContentUnavailableView(
        "Choose a reminder or list",
        systemImage: "list.bullet"
      )
    }
  }
}

#Preview("Empty") {
  let remindersList = try! prepareDependencies {
    try $0.bootstrapDatabase()
    return try $0.defaultDatabase.read { db in
      try RemindersList.all.fetchOne(db)!
    }
  }
  DetailViewController(
    model: AppModel()
  )
}

#Preview("RemindersList") {
  let remindersList = try! prepareDependencies {
    try $0.bootstrapDatabase()
    return try $0.defaultDatabase.read { db in
      try RemindersList.all.fetchOne(db)!
    }
  }
  DetailViewController(
    model: AppModel(
      destination: .remindersList(
        RemindersListDetailModel(
          remindersList: remindersList
        )
      )
    )
  )
}

#Preview("Reminder") {
  let reminder = try! prepareDependencies {
    try $0.bootstrapDatabase()
    return try $0.defaultDatabase.read { db in
      try Reminder.all.fetchOne(db)!
    }
  }
  DetailViewController(
    model: AppModel(
      destination: .reminder(
        ReminderDetailModel(
          reminder: reminder
        )
      )
    )
  )
}
