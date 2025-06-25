import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class NextRecordZoneChangeBatchTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func noMetadataForRecord() async throws {
      privateSyncEngine.state.add(
        pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: UUID(1)))]
      )

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([Reminder.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: []
        )
        """
      }
    }

    @Test func nonExistentTable() async throws {
      try database.syncWrite { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: UnrecognizedTable.tableName,
            recordName: SyncMetadata.RecordName(UnrecognizedTable.self, id: UUID(1))
          )
        }
        .execute(db)
      }
      assertInlineSnapshot(of: privateSyncEngine.state, as: .customDump) {
        """
        MockSyncEngineState(
          pendingRecordZoneChanges: [
            [0]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:unrecognizedTables",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            )
          ],
          pendingDatabaseChanges: []
        )
        """
      }

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([UnrecognizedTable.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: []
        )
        """
      }
    }

    @Test func metadataRowWithNoCorrespondingRecordRow() async throws {
      try database.syncWrite { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: RemindersList.tableName,
            recordName: SyncMetadata.RecordName(RemindersList.self, id: UUID(1))
          )
        }
        .execute(db)
      }
      assertInlineSnapshot(of: privateSyncEngine.state, as: .customDump) {
        """
        MockSyncEngineState(
          pendingRecordZoneChanges: [
            [0]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            )
          ],
          pendingDatabaseChanges: []
        )
        """
      }

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([RemindersList.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: []
        )
        """
      }
    }

    @Test func saveRecord() async throws {
      try database.syncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      assertInlineSnapshot(of: privateSyncEngine.state, as: .customDump) {
        """
        MockSyncEngineState(
          pendingRecordZoneChanges: [
            [0]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            )
          ],
          pendingDatabaseChanges: []
        )
        """
      }

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([RemindersList.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: [
            [0]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "remindersLists",
              share: nil,
              parent: nil,
              id: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Personal"
            )
          ]
        )
        """
      }
    }

    @Test func saveRecordWithParent() async throws {
      try database.syncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      assertInlineSnapshot(of: privateSyncEngine.state, as: .customDump) {
        """
        MockSyncEngineState(
          pendingRecordZoneChanges: [
            [0]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:reminders",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            ),
            [1]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            )
          ],
          pendingDatabaseChanges: []
        )
        """
      }

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([
              RemindersList.recordID(for: UUID(1)),
              Reminder.recordID(for: UUID(1)),
            ])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: [
            [0]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:reminders",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "reminders",
              share: nil,
              parent: CKReference(
                recordID: CKRecordID(
                  recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                  zoneID: CKRecordZoneID(
                    zoneName: "co.pointfree.SQLiteData.defaultZone",
                    ownerName: "__defaultOwner__"
                  )
                )
              ),
              id: "00000000-0000-0000-0000-000000000001",
              remindersListID: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Get milk"
            ),
            [1]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "remindersLists",
              share: nil,
              parent: nil,
              id: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Personal"
            )
          ]
        )
        """
      }
    }

    @Test func savePrivateRecord() async throws {
      try database.syncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersListPrivate(id: UUID(1), position: 42, remindersListID: UUID(1))
        }
      }
      assertInlineSnapshot(of: privateSyncEngine.state, as: .customDump) {
        """
        MockSyncEngineState(
          pendingRecordZoneChanges: [
            [0]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersListPrivates",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            ),
            [1]: .saveRecord(
              CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              )
            )
          ],
          pendingDatabaseChanges: []
        )
        """
      }

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([
              RemindersList.recordID(for: UUID(1)),
              Reminder.recordID(for: UUID(1)),
            ])
          )
        ),
        syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: [
            [0]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersListPrivates",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "remindersListPrivates",
              share: nil,
              parent: nil,
              id: "00000000-0000-0000-0000-000000000001",
              position: 42,
              remindersListID: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
            ),
            [1]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "remindersLists",
              share: nil,
              parent: nil,
              id: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Personal"
            )
          ]
        )
        """
      }
    }
  }
}

@Table struct UnrecognizedTable {
  let id: UUID
}
