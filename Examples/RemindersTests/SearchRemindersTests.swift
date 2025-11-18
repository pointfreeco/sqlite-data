import Dependencies
import DependenciesTestSupport
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  @MainActor
  @Suite(
    .snapshots(record: .missing)
  )
  struct SearchRemindersTests {
    @Dependency(\.defaultDatabase) var database

    @Test func basics() async throws {
      let model = SearchRemindersModel()
      try await model.$searchResults.load()

      #expect(model.searchResults.completedCount == 0)
      assertInlineSnapshot(of: model.searchResults.rows, as: .customDump) {
        """
        []
        """
      }

      model.searchText = "Take"
      try await model.searchTask?.value
      #expect(model.searchResults.completedCount == 1)
      assertInlineSnapshot(of: model.searchResults.rows, as: .customDump) {
        """
        [
          [0]: SearchRemindersModel.Row(
            isPastDue: true,
            notes: "",
            reminder: Reminder(
              id: UUID(00000000-0000-0000-0000-00000000000A),
              dueDate: Date(2009-02-17T23:31:30.000Z),
              isFlagged: false,
              notes: "",
              position: 8,
              priority: .high,
              remindersListID: UUID(00000000-0000-0000-0000-000000000001),
              status: .incomplete,
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            tags: "",
            title: "**Take** out trash"
          )
        ]
        """
      }
    }

    @Test func showCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      try await model.showCompletedButtonTapped()

      assertInlineSnapshot(of: model.searchResults.rows, as: .customDump) {
        """
        []
        """
      }
    }

    @Test func deleteCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      try await model.showCompletedButtonTapped()
      model.deleteCompletedReminders()
      try await model.$searchResults.load()
      #expect(model.searchResults.completedCount == 0)
      assertInlineSnapshot(of: model.searchResults.rows, as: .customDump) {
        """
        []
        """
      }
    }
  }
}
