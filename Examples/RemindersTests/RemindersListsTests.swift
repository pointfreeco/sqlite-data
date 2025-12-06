import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  @MainActor
  struct RemindersListsTests {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.defaultSyncEngine) var syncEngine

    @Test func basics() async throws {
      let model = RemindersListsModel()
      try await model.$remindersLists.load()
      try await model.$stats.load()
      try await model.$tags.load()

      assertInlineSnapshot(of: model.remindersLists, as: .customDump) {
        """
        [
          [0]: RemindersListsModel.ReminderListState(
            remindersCount: 4,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            share: nil
          ),
          [1]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            share: nil
          ),
          [2]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000002),
              color: 2992493567,
              position: 3,
              title: "Business"
            ),
            share: nil
          )
        ]
        """
      }
      assertInlineSnapshot(of: model.stats, as: .customDump) {
        """
        RemindersListsModel.Stats(
          allCount: 8,
          flaggedCount: 2,
          scheduledCount: 7,
          todayCount: 2
        )
        """
      }
      assertInlineSnapshot(of: model.tags, as: .customDump) {
        """
        [
          [0]: Tag(title: "adulting"),
          [1]: Tag(title: "car"),
          [2]: Tag(title: "kids"),
          [3]: Tag(title: "night"),
          [4]: Tag(title: "optional"),
          [5]: Tag(title: "social"),
          [6]: Tag(title: "someday")
        ]
        """
      }
    }

    @Test func move() async throws {
      let model = RemindersListsModel()
      try await model.$remindersLists.load()
      assertInlineSnapshot(of: model.remindersLists.map(\.remindersList.title), as: .customDump) {
        """
        [
          [0]: "Personal",
          [1]: "Family",
          [2]: "Business"
        ]
        """
      }

      model.move(from: [2], to: 0)
      try await model.$remindersLists.load()
      assertInlineSnapshot(of: model.remindersLists.map(\.remindersList.title), as: .customDump) {
        """
        [
          [0]: "Business",
          [1]: "Personal",
          [2]: "Family"
        ]
        """
      }
    }

    @Test func share() async throws {
      let model = RemindersListsModel()

      let personalRemindersList = try #require(
        try await database.read { db in
          try RemindersList.find(UUID(0)).fetchOne(db)
        }
      )
      let _ = try await syncEngine.share(record: personalRemindersList, configure: { _ in })

      try await model.$remindersLists.load()
      assertInlineSnapshot(of: model.remindersLists, as: .customDump) {
        """
        [
          [0]: RemindersListsModel.ReminderListState(
            remindersCount: 4,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: 1218047999,
              position: 1,
              title: "Personal"
            ),
            share: CKShare()
          ),
          [1]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: 3985191935,
              position: 2,
              title: "Family"
            ),
            share: nil
          ),
          [2]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000002),
              color: 2992493567,
              position: 3,
              title: "Business"
            ),
            share: nil
          )
        ]
        """
      }
    }
  }
}
