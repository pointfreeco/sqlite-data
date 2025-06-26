import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SetUpTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func schemaChange() async throws {
      let personalList = RemindersList(id: UUID(1), title: "Personal")
      let businessList = RemindersList(id: UUID(2), title: "Business")
      try database.syncWrite { db in
        try db.seed {
          personalList
          businessList
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      _ = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(),
        syncEngine: privateSyncEngine
      )

      let personalListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1))
      )
      personalListRecord.update(with: personalList, userModificationDate: Date())
      personalListRecord.encryptedValues["position"] = 1
      let businessListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(2))
      )
      businessListRecord.update(with: businessList, userModificationDate: Date())
      businessListRecord.encryptedValues["position"] = 2
      _ = await privateDatabase.modifyRecords(
        saving: [personalListRecord, businessListRecord],
        deleting: [],
        savePolicy: .ifServerRecordUnchanged,
        atomically: true
      )

      try database.syncWrite { db in
        try #sql(
          """
          ALTER TABLE "remindersLists" 
          ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
          """
        )
        .execute(db)
      }

      try await syncEngine.setUpSyncEngine()
      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(),
        syncEngine: privateSyncEngine
      )
      #expect(batch == nil)
      privateSyncEngine.assertFetchChangesScopes([.all])
      sharedSyncEngine.assertFetchChangesScopes([.all])

      let remindersLists = try database.syncRead { db in
        try MigratedRemindersList.order(by: \.id).fetchAll(db)
      }
      expectNoDifference(
        remindersLists,
        [
          MigratedRemindersList(id: UUID(1), title: "Personal", position: 1),
          MigratedRemindersList(id: UUID(2), title: "Business", position: 2),
        ]
      )
    }
  }
}

@Table("remindersLists")
struct MigratedRemindersList: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var position = 0
}
