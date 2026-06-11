#if canImport(CloudKit)
  import CloudKit
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
    @Suite
    final class FetchRecordZoneChangeTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func saveExtraFieldsToSyncMetadata() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue("Hello world! 🌎🌎🌎", forKey: "newField", at: now)

        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

        do {
          let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
            try SyncMetadata
              .order(by: \.recordName)
              .select(\._lastKnownServerRecordAllFields)
              .fetchAll(db)
          }
          assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
            """
            [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                isCompleted: 0,
                newField: "Hello world! 🌎🌎🌎",
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
            """
          }
        }

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.isCompleted.toggle() }.execute(db)
          }

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          do {
            let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
              try SyncMetadata
                .order(by: \.recordName)
                .select(\._lastKnownServerRecordAllFields)
                .fetchAll(db)
            }
            assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
              """
              [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 1,
                  newField: "Hello world! 🌎🌎🌎",
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
              """
            }
          }
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func remoteChangeParentRelationship() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let reminderRecord = try syncEngine.private.database
            .record(for: Reminder.recordID(for: 1))
          reminderRecord.setValue(2, forKey: "remindersListID", at: now)
          reminderRecord.parent = CKRecord.Reference(
            recordID: RemindersList.recordID(for: 2),
            action: .none
          )

          try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
        }

        try await withDependencies {
          $0.currentTime.now += 2
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.isCompleted.toggle() }.execute(db)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌──────────────────────┐
          │ Reminder(            │
          │   id: 1,             │
          │   dueDate: nil,      │
          │   isCompleted: true, │
          │   priority: nil,     │
          │   title: "Get milk", │
          │   remindersListID: 2 │
          │ )                    │
          └──────────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order(by: \.recordName).select { ($0.recordName, $0.parentRecordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┬────────────────────┐
          │ "1:reminders"      │ "2:remindersLists" │
          │ "1:remindersLists" │ nil                │
          │ "2:remindersLists" │ nil                │
          └────────────────────┴────────────────────┘
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
                  parent: CKReference(recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 1,
                  remindersListID: 2,
                  title: "Get milk"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                ),
                [2]: CKRecord(
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
      @Test func editRecordReceivedFromCloudKit() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("1", forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        try await syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]).notify()

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "My stuff" }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          ┌─────────────────────┐
          │ RemindersList(      │
          │   id: 1,            │
          │   title: "My stuff" │
          │ )                   │
          └─────────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order(by: \.recordName).select(\.recordName),
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┐
          │ "1:remindersLists" │
          └────────────────────┘
          """
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
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveNewRecordFromCloudKit_ChildBeforeParent() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("1", forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue("1", forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue("1", forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 1),
          action: .none
        )

        let remindersListModification = try syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
        await remindersListModification.notify()

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Reminder(             │
          │   id: 1,              │
          │   dueDate: nil,       │
          │   isCompleted: false, │
          │   priority: nil,      │
          │   title: "Buy milk",  │
          │   remindersListID: 1  │
          │ )                     │
          └───────────────────────┘
          """
        }
        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          ┌─────────────────────┐
          │ RemindersList(      │
          │   id: 1,            │
          │   title: "Personal" │
          │ )                   │
          └─────────────────────┘
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
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Buy milk"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: "1",
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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteMultipleRecords() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 3, title: "Get milk", remindersListID: 1)
            RemindersList(id: 2, title: "Business")
            Reminder(id: 4, title: "Call accountant", remindersListID: 2)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await syncEngine.modifyRecords(
          scope: .private,
          deleting: [
            RemindersList.recordID(for: 1),
            RemindersList.recordID(for: 2),
            Reminder.recordID(for: 3),
            Reminder.recordID(for: 4),
          ]
        )
        .notify()

        try await userDatabase.read { db in
          try #expect(Reminder.all.fetchCount(db) == 0)
          try #expect(RemindersList.all.fetchCount(db) == 0)
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveRecord_SingleFieldPrimaryKey() async throws {
        let tagRecord = CKRecord(recordType: Tag.tableName, recordID: Tag.recordID(for: "weekend"))
        tagRecord.setValue("weekend", forKey: "title", at: 0)
        try await syncEngine.modifyRecords(scope: .private, saving: [tagRecord]).notify()

        try await userDatabase.read { db in
          try #expect(Tag.all.fetchAll(db) == [Tag(title: "weekend")])
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func renamePrimaryKey() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            Tag(title: "weekend")
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            ReminderTag(id: 1, reminderID: 1, tagID: "weekend")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try Tag.find("weekend").update { $0.title = "optional" }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(SyncMetadata.select(\.recordName), database: userDatabase.database) {
          """
          ┌────────────────────┐
          │ "1:remindersLists" │
          │ "1:reminders"      │
          │ "1:reminderTags"   │
          │ "optional:tags"    │
          └────────────────────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:reminderTags/zone/__defaultOwner__),
                  recordType: "reminderTags",
                  parent: nil,
                  share: nil,
                  id: 1,
                  reminderID: 1,
                  tagID: "optional"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(optional:tags/zone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  title: "optional"
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
      @Test func createTagLocallyThenCreateSameTagRemotely() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            Tag(title: "tag")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let tagRecord = CKRecord(
          recordType: Tag.tableName,
          recordID: Tag.recordID(for: "tag")
        )
        tagRecord.setValue("tag", forKey: "title", at: 0)
        try await syncEngine.modifyRecords(scope: .private, saving: [tagRecord]).notify()

        assertQuery(Tag.all, database: userDatabase.database) {
          """
          ┌───────────────────┐
          │ Tag(title: "tag") │
          └───────────────────┘
          """
        }
        assertQuery(SyncMetadata.all, database: userDatabase.database) {
          """
          ┌────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                              │
          │   id: SyncMetadata.ID(                                     │
          │     recordPrimaryKey: "tag",                               │
          │     recordType: "tags"                                     │
          │   ),                                                       │
          │   zoneName: "zone",                                        │
          │   ownerName: "__defaultOwner__",                           │
          │   recordName: "tag:tags",                                  │
          │   parentRecordID: nil,                                     │
          │   parentRecordName: nil,                                   │
          │   lastKnownServerRecord: CKRecord(                         │
          │     recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                    │
          │     parent: nil,                                           │
          │     share: nil                                             │
          │   ),                                                       │
          │   _lastKnownServerRecordAllFields: CKRecord(               │
          │     recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                    │
          │     parent: nil,                                           │
          │     share: nil,                                            │
          │     title: "tag"                                           │
          │   ),                                                       │
          │   share: nil,                                              │
          │   _pendingStatus: nil,                                     │
          │   _hasLastKnownServerRecord: true,                         │
          │   _isShared: false,                                        │
          │   userModificationTime: 0                                  │
          │ )                                                          │
          └────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  title: "tag"
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
      @Test func createTagRemotelyThenCreateSameTagLocally() async throws {
        let tagRecord = CKRecord(
          recordType: Tag.tableName,
          recordID: Tag.recordID(for: "tag")
        )
        tagRecord.setValue("tag", forKey: "title", at: 0)
        let modifications = try syncEngine.modifyRecords(scope: .private, saving: [tagRecord])

        try await userDatabase.userWrite { db in
          try db.seed {
            Tag(title: "tag")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        await modifications.notify()

        assertQuery(Tag.all, database: userDatabase.database) {
          """
          ┌───────────────────┐
          │ Tag(title: "tag") │
          └───────────────────┘
          """
        }
        assertQuery(SyncMetadata.all, database: userDatabase.database) {
          """
          ┌────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                              │
          │   id: SyncMetadata.ID(                                     │
          │     recordPrimaryKey: "tag",                               │
          │     recordType: "tags"                                     │
          │   ),                                                       │
          │   zoneName: "zone",                                        │
          │   ownerName: "__defaultOwner__",                           │
          │   recordName: "tag:tags",                                  │
          │   parentRecordID: nil,                                     │
          │   parentRecordName: nil,                                   │
          │   lastKnownServerRecord: CKRecord(                         │
          │     recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                    │
          │     parent: nil,                                           │
          │     share: nil                                             │
          │   ),                                                       │
          │   _lastKnownServerRecordAllFields: CKRecord(               │
          │     recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                    │
          │     parent: nil,                                           │
          │     share: nil,                                            │
          │     title: "tag"                                           │
          │   ),                                                       │
          │   share: nil,                                              │
          │   _pendingStatus: nil,                                     │
          │   _hasLastKnownServerRecord: true,                         │
          │   _isShared: false,                                        │
          │   userModificationTime: 0                                  │
          │ )                                                          │
          └────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(tag:tags/zone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  title: "tag"
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

        try await userDatabase.userWrite { db in
          try Tag.find("tag").update { $0.title = "weekend" }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(Tag.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Tag(title: "weekend") │
          └───────────────────────┘
          """
        }
        assertQuery(SyncMetadata.all, database: userDatabase.database) {
          """
          ┌────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                  │
          │   id: SyncMetadata.ID(                                         │
          │     recordPrimaryKey: "weekend",                               │
          │     recordType: "tags"                                         │
          │   ),                                                           │
          │   zoneName: "zone",                                            │
          │   ownerName: "__defaultOwner__",                               │
          │   recordName: "weekend:tags",                                  │
          │   parentRecordID: nil,                                         │
          │   parentRecordName: nil,                                       │
          │   lastKnownServerRecord: CKRecord(                             │
          │     recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                        │
          │     parent: nil,                                               │
          │     share: nil                                                 │
          │   ),                                                           │
          │   _lastKnownServerRecordAllFields: CKRecord(                   │
          │     recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__), │
          │     recordType: "tags",                                        │
          │     parent: nil,                                               │
          │     share: nil,                                                │
          │     title: "weekend"                                           │
          │   ),                                                           │
          │   share: nil,                                                  │
          │   _pendingStatus: nil,                                         │
          │   _hasLastKnownServerRecord: true,                             │
          │   _isShared: false,                                            │
          │   userModificationTime: 0                                      │
          │ )                                                              │
          └────────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  title: "weekend"
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
      @Test func invalidRecordName() async throws {
        let error = await #expect(throws: DatabaseError.self) {
          try await self.userDatabase.userWrite { db in
            try Tag.insert { Tag(title: "_tag") }.execute(db)
          }
        }
        #expect(error?.message == SyncEngine.invalidRecordNameError)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func syncInvalidRecordID() async throws {
        let record = CKRecord(recordType: "foo", recordID: CKRecord.ID(recordName: "bar"))
        try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
      }
    }
  }
#endif
