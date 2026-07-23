#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtrasTestSupport
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.taskLocal(CKRecord._$printTimestamps, true))
    final class MergeConflictTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func merge_clientRecordUpdatedBeforeServerRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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

        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue("Buy milk", forKey: "title", at: 60)
        let modificationCallback = try {
          try syncEngine.modifyRecords(scope: .private, saving: [record])
        }()

        try await withDependencies {
          $0.currentTime.now += 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
          }
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Buy milk",
                  title🗓️: 60,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modificationCallback.notify()

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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 1,
                  isCompleted🗓️: 30,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Buy milk",
                  title🗓️: 60,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func serverRecordUpdatedBeforeClientRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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

        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue("Buy milk", forKey: "title", at: 30)
        let modificationCallback = try {
          try syncEngine.modifyRecords(scope: .private, saving: [record])
        }()

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
          }
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Buy milk",
                  title🗓️: 30,
                  🗓️: 30
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modificationCallback.notify()

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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 1,
                  isCompleted🗓️: 60,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Buy milk",
                  title🗓️: 30,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func serverAndClientEditDifferentFields() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue("Buy milk", forKey: "title", at: 30)
        let modificationCallback = try {
          try syncEngine.modifyRecords(scope: .private, saving: [record])
        }()

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
          }
        }
        await modificationCallback.notify()
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 1,
                  isCompleted🗓️: 60,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Buy milk",
                  title🗓️: 30,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func serverRecordEditedAfterClientButProcessedBeforeClient() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
          }
          try await withDependencies {
            $0.currentTime.now += 30
          } operation: {
            let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
            record.setValue("Buy milk", forKey: "title", at: now)
            let modificationCallback = try {
              try syncEngine.modifyRecords(scope: .private, saving: [record])
            }()

            await modificationCallback.notify()
            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }
        }

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Reminder(             │
          │   id: 1,              │
          │   dueDate: nil,       │
          │   isCompleted: false, │
          │   priority: nil,      │
          │   title: "Get milk",  │
          │   remindersListID: 1  │
          │ )                     │
          └───────────────────────┘
          """
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Get milk",
                  title🗓️: 60,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func serverRecordEditedAndProcessedBeforeClient() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue("Buy milk", forKey: "title", at: 30)
        let modificationCallback = try {
          try syncEngine.modifyRecords(scope: .private, saving: [record])
        }()

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
          }
        }
        await modificationCallback.notify()
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Get milk",
                  title🗓️: 60,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func serverRecordEditedBeforeClientButProcessedAfterClient() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue("Buy milk", forKey: "title", at: 30)
        let modificationCallback = try {
          try syncEngine.modifyRecords(scope: .private, saving: [record])
        }()

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modificationCallback.notify()
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Get milk",
                  title🗓️: 60,
                  🗓️: 60
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func mergeWithNullableFields() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let reminderRecord = try syncEngine.private.database.record(
            for: Reminder.recordID(for: 1)
          )
          reminderRecord.setValue(
            Date(timeIntervalSince1970: Double(30)),
            forKey: "dueDate",
            at: now
          )
          let modificationsFinished = try syncEngine.modifyRecords(
            scope: .private,
            saving: [reminderRecord]
          )

          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try Reminder.find(1).update { $0.priority = #bind(3) }.execute(db)
            }
            await modificationsFinished.notify()
            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }

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
                    dueDate: Date(1970-01-01T00:00:30.000Z),
                    dueDate🗓️: 1,
                    id: 1,
                    id🗓️: 0,
                    isCompleted: 0,
                    isCompleted🗓️: 0,
                    priority: 3,
                    priority🗓️: 2,
                    remindersListID: 1,
                    remindersListID🗓️: 0,
                    title: "",
                    title🗓️: 0,
                    🗓️: 2
                  ),
                  [1]: CKRecord(
                    recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                    recordType: "remindersLists",
                    parent: nil,
                    share: nil,
                    id: 1,
                    id🗓️: 0,
                    title: "Personal",
                    title🗓️: 0,
                    🗓️: 0
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

          try await userDatabase.read { db in
            let reminder = try #require(try Reminder.find(1).fetchOne(db))
            expectNoDifference(
              reminder,
              Reminder(
                id: 1,
                dueDate: Date(timeIntervalSince1970: 30),
                priority: 3,
                remindersListID: 1
              )
            )
          }
        }
      }


      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func equalTimestampConflictConvergesToServerValue() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Mine" }.execute(db)
          }
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
          record.setValue("Theirs", forKey: "title", at: now)
          try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
        }

        assertQuery(Reminder.select(\.title), database: userDatabase.database) {
          """
          ┌──────────┐
          │ "Theirs" │
          └──────────┘
          """
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Theirs",
                  title🗓️: 30,
                  🗓️: 30
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
      @Test func olderTimestampFetchReassertsLocalWinToServer() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "")
            Reminder(id: 1, title: "", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 100
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Fast" }.execute(db)
          }
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
          record.encryptedValues["title"] = "Slow"
          record.encryptedValues["\(CKRecord.userModificationTimeKey)_title"] = Int64(50)
          let modificationCallback = try {
            try syncEngine.modifyRecords(scope: .private, saving: [record])
          }()
          await modificationCallback.notify()
          syncEngine.private.state.assertPendingRecordZoneChanges([
            .saveRecord(Reminder.recordID(for: 1))
          ])
          syncEngine.private.state.add(
            pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: 1))]
          )
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        assertQuery(Reminder.select(\.title), database: userDatabase.database) {
          """
          ┌────────┐
          │ "Fast" │
          └────────┘
          """
        }
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
                  dueDate🗓️: 0,
                  id: 1,
                  id🗓️: 0,
                  isCompleted: 0,
                  isCompleted🗓️: 0,
                  priority🗓️: 0,
                  remindersListID: 1,
                  remindersListID🗓️: 0,
                  title: "Fast",
                  title🗓️: 100,
                  🗓️: 100
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "",
                  title🗓️: 0,
                  🗓️: 0
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
