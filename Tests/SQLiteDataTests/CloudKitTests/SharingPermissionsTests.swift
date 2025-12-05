#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class SharingPermissionsTests: BaseCloudKitTests, @unchecked Sendable {
      /// Inserting record into shared record when user does not have permission should be rejected.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func insertRecordInReadOnlyRemindersList() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        share.publicPermission = .readOnly
        share.currentUserParticipant?.permission = .readOnly

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: remindersListRecord.recordID,
              rootRecord: remindersListRecord,
              share: share
            )
          )

        try await self.userDatabase.userWrite { db in
          let error = #expect(throws: DatabaseError.self) {
            try db.seed {
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            }
          }
          #expect(error?.message == SyncEngine.writePermissionError)
          try #expect(Reminder.all.fetchCount(db) == 0)
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }
      }

      /// Delete record in shared record when user does not have permission.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteReminderInReadOnlyRemindersList() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        reminderRecord.setValue(1, forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue(1, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(record: remindersListRecord, action: .none)
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        share.publicPermission = .readOnly
        share.currentUserParticipant?.permission = .readOnly

        _ = try syncEngine.modifyRecords(
          scope: .shared,
          saving: [reminderRecord, remindersListRecord, share]
        )

        let freshRemindersListRecord = try syncEngine.shared.database.record(
          for: remindersListRecord.recordID
        )
        let freshShare = try #require(
          syncEngine.shared.database.record(for: share.recordID) as? CKShare
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: freshRemindersListRecord.recordID,
              rootRecord: freshRemindersListRecord,
              share: freshShare
            )
          )

        try await self.userDatabase.userWrite { db in
          let error = #expect(throws: DatabaseError.self) {
            try Reminder.find(1).delete().execute(db)
          }
          #expect(error?.message == SyncEngine.writePermissionError)
          try #expect(Reminder.count().fetchOne(db) == 1)
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/external.zone/external.owner),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }
      }

      /// Editing record in shared record when user does not have permission.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func editReminderInReadOnlyRemindersList() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        reminderRecord.setValue(1, forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue(1, forKey: "remindersListID", at: now)
        reminderRecord.setValue(false, forKey: "isCompleted", at: now)
        reminderRecord.parent = CKRecord.Reference(record: remindersListRecord, action: .none)
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        share.publicPermission = .readOnly
        share.currentUserParticipant?.permission = .readOnly
        _ = try syncEngine.modifyRecords(
          scope: .shared,
          saving: [remindersListRecord, reminderRecord, share]
        )

        let freshRemindersListRecord = try syncEngine.shared.database.record(
          for: remindersListRecord.recordID
        )
        let freshShare = try #require(
          syncEngine.shared.database.record(for: share.recordID) as? CKShare
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: freshRemindersListRecord.recordID,
              rootRecord: freshRemindersListRecord,
              share: freshShare
            )
          )

        try await self.userDatabase.userWrite { db in
          let error = #expect(throws: DatabaseError.self) {
            try Reminder.update { $0.isCompleted = true }.execute(db)
          }
          #expect(error?.message == SyncEngine.writePermissionError)
          try #expect(Reminder.where(\.isCompleted).fetchCount(db) == 0)
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/external.zone/external.owner),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Get milk"
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }
      }

      // Edit a record while locally we think we have permission, but CloudKit has newer permissions
      // that are read only.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func createRecordWhenLocalHasPermissionsButCloudKitDoesNot() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        share.publicPermission = .readWrite
        share.currentUserParticipant?.permission = .readWrite

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: remindersListRecord.recordID,
              rootRecord: remindersListRecord,
              share: share
            )
          )

        let freshShare = try syncEngine.shared.database.record(for: share.recordID) as! CKShare
        freshShare.publicPermission = .readOnly
        freshShare.currentUserParticipant?.permission = .readOnly
        let _ = try syncEngine.modifyRecords(scope: .shared, saving: [freshShare])
        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await self.userDatabase.userWrite { db in
            try db.seed {
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            }
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        try await self.userDatabase.read { db in
          try #expect(Reminder.all.fetchCount(db) == 0)
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }
      }

      // Edit a record while locally we think we have permission, but CloudKit has newer permissions
      // that are read only.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func editRecordWhenLocalHasPermissionsButCloudKitDoesNot() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        share.publicPermission = .readWrite
        share.currentUserParticipant?.permission = .readWrite

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: remindersListRecord.recordID,
              rootRecord: remindersListRecord,
              share: share
            )
          )

        let freshShare = try syncEngine.shared.database.record(for: share.recordID) as! CKShare
        freshShare.publicPermission = .readOnly
        freshShare.currentUserParticipant?.permission = .readOnly
        let _ = try syncEngine.modifyRecords(scope: .shared, saving: [freshShare])

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await self.userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Business" }.execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        try await self.userDatabase.read { db in
          try #expect(RemindersList.find(1).fetchOne(db) == RemindersList(id: 1, title: "Personal"))
        }
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }
      }
    }
  }
#endif
