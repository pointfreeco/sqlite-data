import DebugSnapshots
import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import SQLiteData
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  struct RemindersDetailsTests {
    @Dependency(\.defaultDatabase) var database

    @Test func basics() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))
      try await expect(model) {
        try await model.$reminderRows.load()
      } changes: {
        $0.reminderRows = [
          RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(4),
              dueDate: Date(timeIntervalSince1970: 1_234_395_090),
              isFlagged: true,
              position: 2,
              remindersListID: UUID(0),
              title: "Haircut"
            ),
            remindersList: remindersList,
            isPastDue: true,
            notes: "",
            tags: "#someday #optional"
          ),
          RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(5),
              dueDate: Date(timeIntervalSince1970: 1_234_567_890),
              notes: "Ask about diet",
              position: 3,
              priority: .high,
              remindersListID: UUID(0),
              title: "Doctor appointment"
            ),
            remindersList: remindersList,
            isPastDue: false,
            notes: "Ask about diet",
            tags: "#adulting"
          ),
          RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(7),
              dueDate: Date(timeIntervalSince1970: 1_234_567_890),
              position: 5,
              remindersListID: UUID(0),
              title: "Buy concert tickets"
            ),
            remindersList: remindersList,
            isPastDue: false,
            notes: "",
            tags: "#social #night"
          ),
          RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(3),
              notes: """
                Milk
                Eggs
                Apples
                Oatmeal
                Spinach
                """,
              position: 1,
              remindersListID: UUID(0),
              title: "Groceries"
            ),
            remindersList: remindersList,
            isPastDue: false,
            notes: "Milk Eggs Apples Oatmeal Spinach",
            tags: "#someday #optional #adulting"
          ),
        ]
      }
    }

    @Test func ordering() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      expect(model) {
        $0.ordering = .dueDate
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Groceries"
      }

      await model.orderingButtonTapped(.priority)
      try await model.$reminderRows.load()
      expect(model) {
        $0.ordering = .priority
        $0.reminderRows[0].reminder.title = "Doctor appointment"
        $0.reminderRows[1].reminder.title = "Haircut"
        $0.reminderRows[2].reminder.title = "Groceries"
        $0.reminderRows[3].reminder.title = "Buy concert tickets"
      }

      await model.orderingButtonTapped(.title)
      try await model.$reminderRows.load()
      expect(model) {
        $0.ordering = .title
        $0.reminderRows[0].reminder.title = "Buy concert tickets"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Groceries"
        $0.reminderRows[3].reminder.title = "Haircut"
      }
    }

    @Test func showCompleted() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      expect(model) {
        $0.showCompleted = false
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Groceries"
      }

      await model.showCompletedButtonTapped()
      try await model.$reminderRows.load()
      expect(model) {
        $0.showCompleted = true
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Groceries"
        $0.reminderRows[4].reminder.title = "Take a walk"
      }

      await model.showCompletedButtonTapped()
      try await model.$reminderRows.load()
      expect(model) {
        $0.showCompleted = false
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Groceries"
      }
    }

    @Test func move() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Groceries"
      }

      await model.move(from: [2], to: 0)
      try await model.$reminderRows.load()
      expect(model) {
        $0.ordering = .manual
        $0.reminderRows[0].reminder.title = "Buy concert tickets"
        $0.reminderRows[1].reminder.title = "Haircut"
        $0.reminderRows[2].reminder.title = "Doctor appointment"
        $0.reminderRows[3].reminder.title = "Groceries"
      }
    }

    @Test func all() async throws {
      let model = RemindersDetailModel(detailType: .all)
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Pick up kids from school"
        $0.reminderRows[4].reminder.title = "Call accountant"
        $0.reminderRows[5].reminder.title = "Prepare for WWDC"
        $0.reminderRows[6].reminder.title = "Take out trash"
        $0.reminderRows[7].reminder.title = "Groceries"
      }
    }

    @Test func completed() async throws {
      let model = RemindersDetailModel(detailType: .completed)
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Take a walk"
        $0.reminderRows[1].reminder.title = "Get laundry"
        $0.reminderRows[2].reminder.title = "Send weekly emails"
      }
    }

    @Test func flagged() async throws {
      let model = RemindersDetailModel(detailType: .flagged)
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Pick up kids from school"
      }
    }

    @Test func scheduled() async throws {
      let model = RemindersDetailModel(detailType: .scheduled)
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Doctor appointment"
        $0.reminderRows[2].reminder.title = "Buy concert tickets"
        $0.reminderRows[3].reminder.title = "Pick up kids from school"
        $0.reminderRows[4].reminder.title = "Call accountant"
        $0.reminderRows[5].reminder.title = "Prepare for WWDC"
        $0.reminderRows[6].reminder.title = "Take out trash"
      }
    }

    @Test func today() async throws {
      let model = RemindersDetailModel(detailType: .today)
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Doctor appointment"
        $0.reminderRows[1].reminder.title = "Buy concert tickets"
      }
    }

    @Test func tagged() async throws {
      let tag = try await database.read { try Tag.find($0, key: "someday") }
      let model = RemindersDetailModel(detailType: .tags([tag]))
      try await model.$reminderRows.load()
      expect(model) {
        $0.reminderRows[0].reminder.title = "Haircut"
        $0.reminderRows[1].reminder.title = "Groceries"
      }
    }
  }
}
