#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing
  import SQLiteDataTestSupport

  extension BaseCloudKitTests {
    @MainActor
    final class AccountLifecycleTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func signOutClearsUserDatabaseAndMetadatabase() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListPrivate(id: 1, remindersListID: 1)
            UnsyncedModel(id: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await signOut()

        try {
          try userDatabase.userRead { db in
            try #expect(RemindersList.count().fetchOne(db) == 0)
            try #expect(Reminder.count().fetchOne(db) == 0)
            try #expect(RemindersListPrivate.count().fetchOne(db) == 0)
            try #expect(UnsyncedModel.count().fetchOne(db) == 1)
            try #expect(SyncMetadata.count().fetchOne(db) == 0)
          }
        }()
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.accountStatus(.noAccount)) func signInUploadsLocalRecordsToCloudKit() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListPrivate(id: 1, remindersListID: 1)
            UnsyncedModel(id: 1)
          }
        }

        try {
          try userDatabase.read { db in
            try #expect(RemindersList.count().fetchOne(db) == 1)
            try #expect(Reminder.count().fetchOne(db) == 1)
            try #expect(RemindersListPrivate.count().fetchOne(db) == 1)
            try #expect(UnsyncedModel.count().fetchOne(db) == 1)
            try #expect(SyncMetadata.count().fetchOne(db) == 3)
          }
        }()

        await signIn()

        try await syncEngine.processPendingDatabaseChanges(scope: .private)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  position: 0,
                  remindersListID: 1
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                )
              ]
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }
      }
    }

    @MainActor
    @Suite(.accountStatus(.noAccount))
    final class SignedOutTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      init() async throws {
        try await super.init { userDatabase in
          try await userDatabase.write { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
              RemindersListPrivate(id: 1, remindersListID: 1)
              UnsyncedModel(id: 1)
            }
          }
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func doNotUploadExistingDataToCloudKitWhenSignedOut() {
        assertQuery(SyncMetadata.all, database: userDatabase.database)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }
      }
    }
  }
#endif
