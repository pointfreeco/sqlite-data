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
  struct SearchRemindersTests {
    @Dependency(\.defaultDatabase) var database

    @Test func basics() async throws {
      let model = SearchRemindersModel()
      try await model.$searchResults.load()

      try await expect(model) {
        model.searchText = "Take"
        try await model.searchTask?.value
      } changes: {
        $0.searchText = "Take"
        $0.searchResults.completedCount = 1
        $0.searchResults.rows = [
          SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(10),
              dueDate: Date(timeIntervalSince1970: 1_234_913_490),
              position: 8,
              priority: .high,
              remindersListID: UUID(1),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(1),
              color: .family,
              position: 2,
              title: "Family"
            ),
            tags: "",
            title: "**Take** out trash"
          )
        ]
      }
    }

    @Test func showCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      try await model.showCompletedButtonTapped()
      try await model.searchTask?.value
      try await model.$searchResults.load()

      expect(model) {
        $0.searchText = "Take"
        $0.showCompletedInSearchResults = true
        $0.searchResults.completedCount = 1
        $0.searchResults.rows = [
          SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(10),
              dueDate: Date(timeIntervalSince1970: 1_234_913_490),
              position: 8,
              priority: .high,
              remindersListID: UUID(1),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(1),
              color: .family,
              position: 2,
              title: "Family"
            ),
            tags: "",
            title: "**Take** out trash"
          ),
          SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(6),
              dueDate: Date(timeIntervalSince1970: 1_218_151_890),
              position: 4,
              remindersListID: UUID(0),
              status: .completed,
              title: "Take a walk"
            ),
            remindersList: RemindersList(
              id: UUID(0),
              color: .personal,
              position: 1,
              title: "Personal"
            ),
            tags: "#car #kids #social",
            title: "**Take** a walk"
          ),
        ]
      }
    }

    @Test func deleteCompleted() async throws {
      let model = SearchRemindersModel()
      model.searchText = "Take"
      try await model.showCompletedButtonTapped()
      model.deleteCompletedReminders()
      try await model.searchTask?.value
      try await model.$searchResults.load()
      expect(model) {
        $0.searchText = "Take"
        $0.showCompletedInSearchResults = true
        $0.searchResults.completedCount = 0
        $0.searchResults.rows = [
          SearchRemindersModel.Row(
            isPastDue: false,
            notes: "",
            reminder: Reminder(
              id: UUID(10),
              dueDate: Date(timeIntervalSince1970: 1_234_913_490),
              position: 8,
              priority: .high,
              remindersListID: UUID(1),
              title: "Take out trash"
            ),
            remindersList: RemindersList(
              id: UUID(1),
              color: .family,
              position: 2,
              title: "Family"
            ),
            tags: "",
            title: "**Take** out trash"
          )
        ]
      }
    }
  }
}
