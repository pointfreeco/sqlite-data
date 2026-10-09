#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class ReferenceViolationTests: BaseCloudKitTests, @unchecked Sendable {
      // * Local client moves a reminder to a list.
      // * At same time, remote deletes that list.
      // => When data is synchronized the reminder and list are deleted.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func moveReminderToList_RemoteDeletesList() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let modifications = try syncEngine.modifyRecords(
          scope: .private,
          deleting: [RemindersList.recordID(for: 2)]
        )
        try withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.remindersListID = 2 }.execute(db)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modifications.notify()
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(Reminder.find(1).fetchCount(db) == 0)
          try #expect(RemindersList.find(2).fetchCount(db) == 0)
        }
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

        try await userDatabase.read { db in
          try #expect(Reminder.count().fetchOne(db) == 0)
          try #expect(
            RemindersList.all.fetchAll(db) == [
              RemindersList(id: 1, title: "Personal")
            ]
          )
        }
      }

      // * Local client deletes a list
      // * At the same time, remote adds a reminder to that list.
      // * Local data is sync'd first, then remote data syncs.
      // => Deletion is rejected and the list and reminder are sync'd to local client.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteList_RemoteAddsReminderToList() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }
        }
        let modifications = try withDependencies {
          $0.currentTime.now += 2
        } operation: {
          let reminderRecord = CKRecord(
            recordType: Reminder.tableName,
            recordID: Reminder.recordID(for: 1)
          )
          reminderRecord.setValue(1, forKey: "id", at: now)
          reminderRecord.setValue("Get milk", forKey: "title", at: now)
          reminderRecord.setValue(1, forKey: "remindersListID", at: now)
          reminderRecord.parent = CKRecord.Reference(
            recordID: RemindersList.recordID(for: 1),
            action: .none
          )
          return try syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modifications.notify()

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
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [1]: CKRecord(
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

        try await userDatabase.read { db in
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
          try #expect(
            RemindersList.all.fetchAll(db) == [RemindersList(id: 1, title: "Personal")]
          )
        }
      }

      // * Local client deletes a list
      // * At the same time, remote adds a reminder to that list.
      // * Remote data is sync'd first, then local data syncs.
      // => Deletion is rejected and the list and reminder are sync'd to local client.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteList_RemoteAddsReminderToList_Variation() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }
        }
        let modifications = try withDependencies {
          $0.currentTime.now += 2
        } operation: {
          let reminderRecord = CKRecord(
            recordType: Reminder.tableName,
            recordID: Reminder.recordID(for: 1)
          )
          reminderRecord.setValue(1, forKey: "id", at: now)
          reminderRecord.setValue("Get milk", forKey: "title", at: now)
          reminderRecord.setValue(1, forKey: "remindersListID", at: now)
          reminderRecord.parent = CKRecord.Reference(
            recordID: RemindersList.recordID(for: 1),
            action: .none
          )
          return try syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        }
        await modifications.notify()
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
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [1]: CKRecord(
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

        try await userDatabase.read { db in
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
          try #expect(
            RemindersList.all.fetchAll(db) == [RemindersList(id: 1, title: "Personal")]
          )
        }
      }

      // * Local client move child to parent.
      // * Remote client deletes parent.
      // * Local data is sync'd first, then remote data syncs.
      // => Local client sets parent relationship to NULL and parent is deleted.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func moveChildToParent_RemoteDeletesParent_CascadeSetNull() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            Parent(id: 1)
            Parent(id: 2)
            ChildWithOnDeleteSetNull(id: 1, parentID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let modifications = try syncEngine.modifyRecords(
          scope: .private,
          deleting: [Parent.recordID(for: 2)]
        )
        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try ChildWithOnDeleteSetNull.find(1).update { $0.parentID = #bind(2) }.execute(db)
          }
        }
        try await withDependencies {
          $0.currentTime.now += 2
        } operation: {
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          await modifications.notify()
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          assertInlineSnapshot(of: container, as: .customDump) {
            """
            MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(
                databaseScope: .private,
                storage: [
                  [0]: CKRecord(
                    recordID: CKRecord.ID(1:childWithOnDeleteSetNulls/zone/__defaultOwner__),
                    recordType: "childWithOnDeleteSetNulls",
                    parent: nil,
                    share: nil,
                    id: 1
                  ),
                  [1]: CKRecord(
                    recordID: CKRecord.ID(1:parents/zone/__defaultOwner__),
                    recordType: "parents",
                    parent: nil,
                    share: nil,
                    id: 1
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
          assertQuery(ChildWithOnDeleteSetNull.all, database: userDatabase.database) {
            """
            ┌───────────────────────────┐
            │ ChildWithOnDeleteSetNull( │
            │   id: 1,                  │
            │   parentID: nil           │
            │ )                         │
            └───────────────────────────┘
            """
          }
          assertQuery(Parent.all, database: userDatabase.database) {
            """
            ┌───────────────┐
            │ Parent(id: 1) │
            └───────────────┘
            """
          }
        }
      }

      // * Local client move child to parent.
      // * Remote client deletes parent.
      // * Local data is sync'd first, then remote data syncs.
      // => Local client sets parent relationship to default value.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func moveChildToParent_RemoteDeletesParent_CascadeSetDefault() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            Parent(id: 0)
            Parent(id: 1)
            Parent(id: 2)
            ChildWithOnDeleteSetDefault(id: 1, parentID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let modifications = try syncEngine.modifyRecords(
          scope: .private,
          deleting: [Parent.recordID(for: 2)]
        )
        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try ChildWithOnDeleteSetDefault.find(1).update { $0.parentID = 2 }.execute(db)
          }
        }
        try await withDependencies {
          $0.currentTime.now += 2
        } operation: {
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          await modifications.notify()
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          assertInlineSnapshot(of: container, as: .customDump) {
            """
            MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(
                databaseScope: .private,
                storage: [
                  [0]: CKRecord(
                    recordID: CKRecord.ID(1:childWithOnDeleteSetDefaults/zone/__defaultOwner__),
                    recordType: "childWithOnDeleteSetDefaults",
                    parent: CKReference(recordID: CKRecord.ID(0:parents/zone/__defaultOwner__)),
                    share: nil,
                    id: 1,
                    parentID: 0
                  ),
                  [1]: CKRecord(
                    recordID: CKRecord.ID(0:parents/zone/__defaultOwner__),
                    recordType: "parents",
                    parent: nil,
                    share: nil,
                    id: 0
                  ),
                  [2]: CKRecord(
                    recordID: CKRecord.ID(1:parents/zone/__defaultOwner__),
                    recordType: "parents",
                    parent: nil,
                    share: nil,
                    id: 1
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
            try #expect(
              ChildWithOnDeleteSetDefault.all.fetchAll(db) == [
                ChildWithOnDeleteSetDefault(id: 1, parentID: 0)
              ]
            )
            try #expect(
              Parent.all.fetchAll(db) == [Parent(id: 0), Parent(id: 1)]
            )
          }
        }
      }

      // * Local client adds a list, but its save fails and is not retried (e.g. with an error that
      //   is not retried, or by an older version of the library).
      // * Local client adds a reminder to that list.
      // => Reminder is rejected because the list is not on the server, but is not deleted. List and
      //    reminder are both sent again and uploaded.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addReminderToListThatWasNeverUploaded() async throws {
        setQuotaExceeded(true)
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        syncEngine.private.state.remove(
          pendingRecordZoneChanges: [.saveRecord(RemindersList.recordID(for: 1))]
        )
        setQuotaExceeded(false)

        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(RemindersList.all.fetchAll(db) == [RemindersList(id: 1, title: "Personal")])
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
        }
        #expect(
          Set(syncEngine.private.state.pendingRecordZoneChanges) == [
            .saveRecord(RemindersList.recordID(for: 1)),
            .saveRecord(Reminder.recordID(for: 1)),
          ]
        )

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

      // * Local client saves a list and a reminder.
      // * List is rejected for a reason that is not retried, and reminder is rejected with a
      //   reference violation in the same batch.
      // => Reminder is not deleted, and neither record is sent again.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func listRejectedInSameBatchAsReminderReferenceViolation() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        let batch = await syncEngine.nextRecordZoneChangeBatch(syncEngine: syncEngine.private)
        let recordsToSave = try #require(batch?.recordsToSave)
        let remindersListRecord = try #require(
          recordsToSave.first { $0.recordID == RemindersList.recordID(for: 1) }
        )
        let reminderRecord = try #require(
          recordsToSave.first { $0.recordID == Reminder.recordID(for: 1) }
        )
        syncEngine.private.state.remove(
          pendingRecordZoneChanges: recordsToSave.map { .saveRecord($0.recordID) }
        )

        await syncEngine.handleEvent(
          .sentRecordZoneChanges(
            savedRecords: [],
            failedRecordSaves: [
              (record: remindersListRecord, error: CKError(.serverRejectedRequest)),
              (record: reminderRecord, error: CKError(.referenceViolation)),
            ],
            deletedRecordIDs: [],
            failedRecordDeletes: [:]
          ),
          syncEngine: syncEngine.private
        )

        try await userDatabase.read { db in
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
        }
        #expect(syncEngine.private.state.pendingRecordZoneChanges.isEmpty)
      }
    }
  }
#endif
