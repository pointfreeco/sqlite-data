import CloudKit
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
  struct RemindersListsTests {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.defaultSyncEngine) var syncEngine

    @Test func basics() async throws {
      let model = RemindersListsModel()
      try await expect(model) {
        try await model.$remindersLists.load()
        try await model.$stats.load()
        try await model.$tags.load()
      } changes: {
        $0.remindersLists = [
          RemindersListsModel.ReminderListState(
            remindersCount: 4,
            remindersList: RemindersList(
              id: UUID(0),
              color: .personal,
              position: 1,
              title: "Personal"
            ),
            share: nil
          ),
          RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(1),
              color: .family,
              position: 2,
              title: "Family"
            ),
            share: nil
          ),
          RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(2),
              color: .business,
              position: 3,
              title: "Business"
            ),
            share: nil
          ),
        ]
        $0.stats = RemindersListsModel.Stats(
          allCount: 8,
          flaggedCount: 2,
          scheduledCount: 7,
          todayCount: 2
        )
        $0.tags = [
          Tag(title: "adulting"),
          Tag(title: "car"),
          Tag(title: "kids"),
          Tag(title: "night"),
          Tag(title: "optional"),
          Tag(title: "social"),
          Tag(title: "someday"),
        ]
      }
    }

    @Test func move() async throws {
      let model = RemindersListsModel()

      try await expect(model) {
        try await model.$remindersLists.load()
      } changes: {
        $0.remindersLists[0].remindersList.title = "Personal"
        $0.remindersLists[1].remindersList.title = "Family"
        $0.remindersLists[2].remindersList.title = "Business"
      }

      try await expect(model) {
        model.move(from: [2], to: 0)
        try await model.$remindersLists.load()
      } changes: {
        $0.remindersLists.move(fromOffsets: [2], toOffset: 0)
        $0.remindersLists[0].remindersList.position = 1
        $0.remindersLists[1].remindersList.position = 2
        $0.remindersLists[2].remindersList.position = 3
      }
    }

    @Test func share() async throws {
      let model = RemindersListsModel()

      let personalRemindersList = try #require(
        try await database.read { db in
          try RemindersList.find(UUID(0)).fetchOne(db)
        }
      )
      let share = try await syncEngine.share(
        record: personalRemindersList,
        configure: { _ in }
      )
        .share

      try await expect(model) {
        try await model.$remindersLists.load()
      } changes: {
        $0.remindersLists[0].remindersList.title = "Personal"
        $0.remindersLists[0].share = model.remindersLists[0].share
        #expect($0.remindersLists[0].share?.recordID == share.recordID)
      }
    }
  }
}
