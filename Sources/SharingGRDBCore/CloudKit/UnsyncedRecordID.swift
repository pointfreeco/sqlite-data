#if canImport(CloudKit)
  import CloudKit
  import StructuredQueriesCore

  // @Table("\(String.sqliteDataCloudKitSchemaName)_unsyncedRecordIDs")
package struct UnsyncedRecordID: Equatable {
    package let recordName: String
    package let zoneName: String
    package let ownerName: String
  }

  extension UnsyncedRecordID {
    package init(recordID: CKRecord.ID) {
      recordName = recordID.recordName
      zoneName = recordID.zoneID.zoneName
      ownerName = recordID.zoneID.ownerName
    }
    package static func find(_ recordID: CKRecord.ID) -> Where<UnsyncedRecordID> {
      Self.where {
        $0.recordName.eq(recordID.recordName)
        && $0.zoneName.eq(recordID.zoneID.zoneName)
        && $0.ownerName.eq(recordID.zoneID.ownerName)
      }
    }
  }

  extension CKRecord.ID {
    convenience init(unsyncedRecordID: UnsyncedRecordID) {
      self.init(
        recordName: unsyncedRecordID.recordName,
        zoneID:
          CKRecordZone
          .ID(
            zoneName: unsyncedRecordID.zoneName,
            ownerName: unsyncedRecordID.ownerName
          )
      )
    }
  }
#endif
