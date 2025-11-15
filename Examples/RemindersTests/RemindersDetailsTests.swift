import Dependencies
import DependenciesTestSupport
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  @MainActor
  struct RemindersDetailsTests {
    @Dependency(\.defaultDatabase) var database

    @Test func basics() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows, as: .customDump) {
        #"""
        [
          [0]: RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-000000000004),
              dueDate: Date(2009-02-11T23:31:30.000Z),
              isFlagged: true,
              notes: "",
              position: 2,
              priority: nil,
              remindersListID: UUID(00000000-0000-0000-0000-000000000000),
              status: .incomplete,
              title: "Haircut"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            isPastDue: true,
            notes: "",
            tags: "#someday #optional"
          ),
          [1]: RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-000000000005),
              dueDate: Date(2009-02-13T23:31:30.000Z),
              isFlagged: false,
              notes: "Ask about diet",
              position: 3,
              priority: .high,
              remindersListID: UUID(00000000-0000-0000-0000-000000000000),
              status: .incomplete,
              title: "Doctor appointment"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            isPastDue: false,
            notes: "Ask about diet",
            tags: "#adulting"
          ),
          [2]: RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-000000000007),
              dueDate: Date(2009-02-13T23:31:30.000Z),
              isFlagged: false,
              notes: "",
              position: 5,
              priority: nil,
              remindersListID: UUID(00000000-0000-0000-0000-000000000000),
              status: .incomplete,
              title: "Buy concert tickets"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            isPastDue: false,
            notes: "",
            tags: "#social #night"
          ),
          [3]: RemindersDetailModel.Row(
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-000000000003),
              dueDate: nil,
              isFlagged: false,
              notes: """
                Milk
                Eggs
                Apples
                Oatmeal
                Spinach
                """,
              position: 1,
              priority: nil,
              remindersListID: UUID(00000000-0000-0000-0000-000000000000),
              status: .incomplete,
              title: "Groceries"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            isPastDue: false,
            notes: "Milk Eggs Apples Oatmeal Spinach",
            tags: "#someday #optional #adulting"
          )
        ]
        """#
      }
    }

    @Test func ordering() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      #expect(model.ordering == .dueDate)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Groceries"
        ]
        """
      }

      await model.orderingButtonTapped(.priority)
      try await model.$reminderRows.load()
      #expect(model.ordering == .priority)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Doctor appointment",
          [1]: "Haircut",
          [2]: "Groceries",
          [3]: "Buy concert tickets"
        ]
        """
      }

      await model.orderingButtonTapped(.title)
      try await model.$reminderRows.load()
      #expect(model.ordering == .title)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Buy concert tickets",
          [1]: "Doctor appointment",
          [2]: "Groceries",
          [3]: "Haircut"
        ]
        """
      }
    }

    @Test func showCompleted() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      #expect(model.showCompleted == false)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Groceries"
        ]
        """
      }

      await model.showCompletedButtonTapped()
      try await model.$reminderRows.load()
      #expect(model.showCompleted == true)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Groceries",
          [4]: "Take a walk"
        ]
        """
      }

      await model.showCompletedButtonTapped()
      try await model.$reminderRows.load()
      #expect(model.showCompleted == false)
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Groceries"
        ]
        """
      }
    }

    @Test func move() async throws {
      let remindersList = try await database.read { try RemindersList.fetchOne($0)! }
      let model = RemindersDetailModel(detailType: .remindersList(remindersList))

      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Groceries"
        ]
        """
      }

      await model.move(from: [2], to: 0)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Buy concert tickets",
          [1]: "Haircut",
          [2]: "Doctor appointment",
          [3]: "Groceries"
        ]
        """
      }
      #expect(model.ordering == .manual)
    }

    @Test func all() async throws {
      let model = RemindersDetailModel(detailType: .all)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Pick up kids from school",
          [4]: "Call accountant",
          [5]: "Prepare for WWDC",
          [6]: "Take out trash",
          [7]: "Groceries"
        ]
        """
      }
    }

    @Test func completed() async throws {
      let model = RemindersDetailModel(detailType: .completed)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Take a walk",
          [1]: "Get laundry",
          [2]: "Send weekly emails"
        ]
        """
      }
    }

    @Test func flagged() async throws {
      let model = RemindersDetailModel(detailType: .flagged)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Pick up kids from school"
        ]
        """
      }
    }

    @Test func scheduled() async throws {
      let model = RemindersDetailModel(detailType: .scheduled)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Doctor appointment",
          [2]: "Buy concert tickets",
          [3]: "Pick up kids from school",
          [4]: "Call accountant",
          [5]: "Prepare for WWDC",
          [6]: "Take out trash"
        ]
        """
      }
    }

    @Test func today() async throws {
      let model = RemindersDetailModel(detailType: .today)
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Doctor appointment",
          [1]: "Buy concert tickets"
        ]
        """
      }
    }

    @Test func tagged() async throws {
      let tag = try await database.read { try Tag.find($0, key: "someday") }
      let model = RemindersDetailModel(detailType: .tags([tag]))
      try await model.$reminderRows.load()
      assertInlineSnapshot(of: model.reminderRows.map(\.reminder.title), as: .customDump) {
        """
        [
          [0]: "Haircut",
          [1]: "Groceries"
        ]
        """
      }
    }
  }
}
