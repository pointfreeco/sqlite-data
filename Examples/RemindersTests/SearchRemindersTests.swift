import Dependencies
import DependenciesTestSupport
import InlineSnapshotTesting
import GRDB
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  @MainActor
  struct SearchRemindersTests {
    @Dependency(\.defaultDatabase) var database

    @Test func basics() async throws {
      let model = SearchRemindersModel()
      try await model.$reminders.load()
      try await model.$completedCount.load()

      #expect(model.completedCount == 0)
      assertInlineSnapshot(of: model.reminders, as: .customDump) {
        """
        []
        """
      }

      model.searchText = "Take"
      try await model.$reminders.load()
      try await model.$completedCount.load()
      try await Task.sleep(for: .seconds(0.5))
      #expect(model.completedCount == 1)
      assertInlineSnapshot(of: model.reminders, as: .customDump) {
        """
        [
          [0]: SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-00000000000A),
              dueDate: Date(2009-02-17T23:31:30.000Z),
              isCompleted: false,
              isFlagged: false,
              notes: "",
              position: 8,
              priority: .high,
              remindersListID: UUID(00000000-0000-0000-0000-000000000001),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            tags: []
          )
        ]
        """
      }
    }

    @Test func showCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      await model.showCompletedButtonTapped()
      try await Task.sleep(for: .seconds(0.1))
      try await model.$reminders.load()
      try await model.$completedCount.load()

      assertInlineSnapshot(of: model.reminders, as: .customDump) {
        """
        [
          [0]: SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-00000000000A),
              dueDate: Date(2009-02-17T23:31:30.000Z),
              isCompleted: false,
              isFlagged: false,
              notes: "",
              position: 8,
              priority: .high,
              remindersListID: UUID(00000000-0000-0000-0000-000000000001),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            tags: []
          ),
          [1]: SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-000000000006),
              dueDate: Date(2008-08-07T23:31:30.000Z),
              isCompleted: true,
              isFlagged: false,
              notes: "",
              position: 4,
              priority: nil,
              remindersListID: UUID(00000000-0000-0000-0000-000000000000),
              title: "Take a walk"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            tags: [
              [0]: "car",
              [1]: "kids",
              [2]: "social"
            ]
          )
        ]
        """
      }
    }

    @Test func deleteCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      await model.showCompletedButtonTapped()
      try await Task.sleep(for: .seconds(0.1))
      model.deleteCompletedReminders()
      try await model.$reminders.load()
      try await model.$completedCount.load()
      #expect(model.completedCount == 0)
      assertInlineSnapshot(of: model.reminders, as: .customDump) {
        """
        [
          [0]: SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-00000000000A),
              dueDate: Date(2009-02-17T23:31:30.000Z),
              isCompleted: false,
              isFlagged: false,
              notes: "",
              position: 8,
              priority: .high,
              remindersListID: UUID(00000000-0000-0000-0000-000000000001),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            tags: []
          )
        ]
        """
      }
    }
  }
}
