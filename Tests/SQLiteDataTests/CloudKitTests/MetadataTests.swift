#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import SQLiteDataTestSupport
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class MetadataTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func parentRecordNameUpdatesAfterMovingReminderToDifferentList() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Work")
            Reminder(id: 1, title: "Groceries", remindersListID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try userDatabase.userWrite { db in
            try Reminder.find(1)
              .update { $0.remindersListID = 2 }
              .execute(db)
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
          │   title: "Groceries", │
          │   remindersListID: 2  │
          │ )                     │
          └───────────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.select { ($0.recordName, $0.parentRecordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┬────────────────────┐
          │ "1:remindersLists" │ nil                │
          │ "2:remindersLists" │ nil                │
          │ "1:reminders"      │ "2:remindersLists" │
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
                  isCompleted: 0,
                  remindersListID: 2,
                  title: "Groceries"
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
                  title: "Work"
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

      // 'parent' association is not set on CKRecord for records with multiple foreign keys.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func noParentRecordForRecordsWithMultipleForeignKeys() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Groceries", remindersListID: 1)
            Tag(title: "weekend")
            ReminderTag(id: 1, reminderID: 1, tagID: "weekend")
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
                  recordID: CKRecord.ID(1:reminderTags/zone/__defaultOwner__),
                  recordType: "reminderTags",
                  parent: nil,
                  share: nil,
                  id: 1,
                  reminderID: 1,
                  tagID: "weekend"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Groceries"
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

        assertQuery(
          SyncMetadata.order(by: \.recordName).select { ($0.recordName, $0.parentRecordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┬────────────────────┐
          │ "1:reminderTags"   │ nil                │
          │ "1:reminders"      │ "1:remindersLists" │
          │ "1:remindersLists" │ nil                │
          │ "weekend:tags"     │ nil                │
          └────────────────────┴────────────────────┘
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func metadataFields() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            Reminder(id: 1, title: "Groceries", remindersListID: 1)
            Reminder(id: 2, title: "Take a walk", remindersListID: 1)
            Reminder(id: 3, title: "Call accountant", remindersListID: 2)
            Tag(title: "weekend")
            Tag(title: "optional")
            ReminderTag(id: 1, reminderID: 1, tagID: "weekend")
            ReminderTag(id: 2, reminderID: 2, tagID: "weekend")
            ReminderTag(id: 3, reminderID: 3, tagID: "optional")
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          SyncMetadata.order(by: \.recordName),
          database: syncEngine.metadatabase
        ) {
          """
          ┌─────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "1",                                                              │
          │     recordType: "reminderTags"                                                          │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "1:reminderTags",                                                         │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     id: 1,                                                                              │
          │     reminderID: 1,                                                                      │
          │     tagID: "weekend"                                                                    │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "1",                                                              │
          │     recordType: "reminders"                                                             │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "1:reminders",                                                            │
          │   parentRecordID: SyncMetadata.ParentID(                                                │
          │     parentRecordPrimaryKey: "1",                                                        │
          │     parentRecordType: "remindersLists"                                                  │
          │   ),                                                                                    │
          │   parentRecordName: "1:remindersLists",                                                 │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │     share: nil,                                                                         │
          │     id: 1,                                                                              │
          │     isCompleted: 0,                                                                     │
          │     remindersListID: 1,                                                                 │
          │     title: "Groceries"                                                                  │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "1",                                                              │
          │     recordType: "remindersLists"                                                        │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "1:remindersLists",                                                       │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),                      │
          │     recordType: "remindersLists",                                                       │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),                      │
          │     recordType: "remindersLists",                                                       │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     id: 1,                                                                              │
          │     title: "Personal"                                                                   │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "2",                                                              │
          │     recordType: "reminderTags"                                                          │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "2:reminderTags",                                                         │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(2:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(2:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     id: 2,                                                                              │
          │     reminderID: 2,                                                                      │
          │     tagID: "weekend"                                                                    │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "2",                                                              │
          │     recordType: "reminders"                                                             │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "2:reminders",                                                            │
          │   parentRecordID: SyncMetadata.ParentID(                                                │
          │     parentRecordPrimaryKey: "1",                                                        │
          │     parentRecordType: "remindersLists"                                                  │
          │   ),                                                                                    │
          │   parentRecordName: "1:remindersLists",                                                 │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(2:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(2:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │     share: nil,                                                                         │
          │     id: 2,                                                                              │
          │     isCompleted: 0,                                                                     │
          │     remindersListID: 1,                                                                 │
          │     title: "Take a walk"                                                                │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "2",                                                              │
          │     recordType: "remindersLists"                                                        │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "2:remindersLists",                                                       │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__),                      │
          │     recordType: "remindersLists",                                                       │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__),                      │
          │     recordType: "remindersLists",                                                       │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     id: 2,                                                                              │
          │     title: "Business"                                                                   │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "3",                                                              │
          │     recordType: "reminderTags"                                                          │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "3:reminderTags",                                                         │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(3:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(3:reminderTags/zone/__defaultOwner__),                        │
          │     recordType: "reminderTags",                                                         │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     id: 3,                                                                              │
          │     reminderID: 3,                                                                      │
          │     tagID: "optional"                                                                   │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "3",                                                              │
          │     recordType: "reminders"                                                             │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "3:reminders",                                                            │
          │   parentRecordID: SyncMetadata.ParentID(                                                │
          │     parentRecordPrimaryKey: "2",                                                        │
          │     parentRecordType: "remindersLists"                                                  │
          │   ),                                                                                    │
          │   parentRecordName: "2:remindersLists",                                                 │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(3:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__)), │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(3:reminders/zone/__defaultOwner__),                           │
          │     recordType: "reminders",                                                            │
          │     parent: CKReference(recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__)), │
          │     share: nil,                                                                         │
          │     id: 3,                                                                              │
          │     isCompleted: 0,                                                                     │
          │     remindersListID: 2,                                                                 │
          │     title: "Call accountant"                                                            │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "optional",                                                       │
          │     recordType: "tags"                                                                  │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "optional:tags",                                                          │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(optional:tags/zone/__defaultOwner__),                         │
          │     recordType: "tags",                                                                 │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(optional:tags/zone/__defaultOwner__),                         │
          │     recordType: "tags",                                                                 │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     title: "optional"                                                                   │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   id: SyncMetadata.ID(                                                                  │
          │     recordPrimaryKey: "weekend",                                                        │
          │     recordType: "tags"                                                                  │
          │   ),                                                                                    │
          │   zoneName: "zone",                                                                     │
          │   ownerName: "__defaultOwner__",                                                        │
          │   recordName: "weekend:tags",                                                           │
          │   parentRecordID: nil,                                                                  │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__),                          │
          │     recordType: "tags",                                                                 │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__),                          │
          │     recordType: "tags",                                                                 │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     title: "weekend"                                                                    │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationTime: 0                                                               │
          │ )                                                                                       │
          └─────────────────────────────────────────────────────────────────────────────────────────┘
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func hasMetadataHelper() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Work")
            Reminder(id: 1, title: "Groceries", remindersListID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          RemindersList.join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) },
          database: userDatabase.database
        ) {
          """
          ┌─────────────────────┬────────────────────────────────────────────────────────────────────┐
          │ RemindersList(      │ SyncMetadata(                                                      │
          │   id: 1,            │   id: SyncMetadata.ID(                                             │
          │   title: "Personal" │     recordPrimaryKey: "1",                                         │
          │ )                   │     recordType: "remindersLists"                                   │
          │                     │   ),                                                               │
          │                     │   zoneName: "zone",                                                │
          │                     │   ownerName: "__defaultOwner__",                                   │
          │                     │   recordName: "1:remindersLists",                                  │
          │                     │   parentRecordID: nil,                                             │
          │                     │   parentRecordName: nil,                                           │
          │                     │   lastKnownServerRecord: CKRecord(                                 │
          │                     │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │                     │     recordType: "remindersLists",                                  │
          │                     │     parent: nil,                                                   │
          │                     │     share: nil                                                     │
          │                     │   ),                                                               │
          │                     │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │                     │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │                     │     recordType: "remindersLists",                                  │
          │                     │     parent: nil,                                                   │
          │                     │     share: nil,                                                    │
          │                     │     id: 1,                                                         │
          │                     │     title: "Personal"                                              │
          │                     │   ),                                                               │
          │                     │   share: nil,                                                      │
          │                     │   _isDeleted: false,                                               │
          │                     │   hasLastKnownServerRecord: true,                                  │
          │                     │   isShared: false,                                                 │
          │                     │   userModificationTime: 0                                          │
          │                     │ )                                                                  │
          ├─────────────────────┼────────────────────────────────────────────────────────────────────┤
          │ RemindersList(      │ SyncMetadata(                                                      │
          │   id: 2,            │   id: SyncMetadata.ID(                                             │
          │   title: "Work"     │     recordPrimaryKey: "2",                                         │
          │ )                   │     recordType: "remindersLists"                                   │
          │                     │   ),                                                               │
          │                     │   zoneName: "zone",                                                │
          │                     │   ownerName: "__defaultOwner__",                                   │
          │                     │   recordName: "2:remindersLists",                                  │
          │                     │   parentRecordID: nil,                                             │
          │                     │   parentRecordName: nil,                                           │
          │                     │   lastKnownServerRecord: CKRecord(                                 │
          │                     │     recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__), │
          │                     │     recordType: "remindersLists",                                  │
          │                     │     parent: nil,                                                   │
          │                     │     share: nil                                                     │
          │                     │   ),                                                               │
          │                     │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │                     │     recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__), │
          │                     │     recordType: "remindersLists",                                  │
          │                     │     parent: nil,                                                   │
          │                     │     share: nil,                                                    │
          │                     │     id: 2,                                                         │
          │                     │     title: "Work"                                                  │
          │                     │   ),                                                               │
          │                     │   share: nil,                                                      │
          │                     │   _isDeleted: false,                                               │
          │                     │   hasLastKnownServerRecord: true,                                  │
          │                     │   isShared: false,                                                 │
          │                     │   userModificationTime: 0                                          │
          │                     │ )                                                                  │
          └─────────────────────┴────────────────────────────────────────────────────────────────────┘
          """
        }
      }
    }
  }
#endif
