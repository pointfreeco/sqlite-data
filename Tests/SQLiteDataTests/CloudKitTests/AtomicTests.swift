#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class AtomicTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func editConflictAndNewRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let remindersListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("My stuff", forKey: "title", at: 1)
        let (saveResults, _) = try syncEngine.private.database.modifyRecords(saving: [
          remindersListRecord
        ])
        #expect(saveResults.values.allSatisfy { $0.error == nil })

        try await withDependencies {
          $0.currentTime.now = 2
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Stuff" }.execute(db)
            try RemindersList.insert { RemindersList(id: 2, title: "Business") }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(
          scope: .private,
          forceAtomicByZone: true
        )

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "My stuff"
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

        try await syncEngine.processPendingRecordZoneChanges(
          scope: .private,
          forceAtomicByZone: true
        )

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Stuff"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 2,
                  title: "Business"
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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func editConflictAndDeleteRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(
          scope: .private,
          forceAtomicByZone: true
        )

        let remindersListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("My stuff", forKey: "title", at: 1)
        let (saveResults, _) = try syncEngine.private.database.modifyRecords(saving: [
          remindersListRecord
        ])
        #expect(saveResults.values.allSatisfy { $0.error == nil })

        try await withDependencies {
          $0.currentTime.now = 2
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Stuff" }.execute(db)
            try RemindersList.find(2).delete().execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(
          scope: .private,
          forceAtomicByZone: true
        )

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "My stuff"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 2,
                  title: "Business"
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

        try await syncEngine.processPendingRecordZoneChanges(
          scope: .private,
          forceAtomicByZone: true
        )

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Stuff"
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
  }
#endif
