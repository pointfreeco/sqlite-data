#if canImport(CloudKit)
  import CloudKit
  import StructuredQueriesCore

  @Table("sqlitedata_icloud_unsyncedRecordIDs")
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
    package static func findAll(_ recordIDs: some Collection<CKRecord.ID>) -> Where<
      UnsyncedRecordID
    > {
      let condition: QueryFragment = recordIDs.map {
        "(\(bind: $0.recordName), \(bind: $0.zoneID.zoneName), \(bind: $0.zoneID.ownerName))"
      }
      .joined(separator: ", ")
      return Self.where {
        SQLQueryExpression(
          """
          (\($0.recordName), \($0.zoneName), \($0.ownerName)) \
          IN (\(condition))
          """
        )
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
