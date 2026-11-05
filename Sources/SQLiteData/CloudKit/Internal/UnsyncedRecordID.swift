#if canImport(CloudKit)
  package import CloudKit
  import Dependencies
  import StructuredQueries
  package import StructuredQueriesCore

  @Table("sqlitedata_icloud_unsyncedRecordIDs")
  package struct UnsyncedRecordID: Equatable {
    package let recordName: String
    package let zoneName: String
    package let ownerName: String
    @Column(as: [String: Data].JSONRepresentation.self)
    package let assets: [String: Data]
    @Column(as: CKRecord?._AllFieldsRepresentation.self)
    package let record: CKRecord?
  }

  extension UnsyncedRecordID {
    private init(recordID: CKRecord.ID, assets: [String: Data], record: CKRecord?) {
      recordName = recordID.recordName
      zoneName = recordID.zoneID.zoneName
      ownerName = recordID.zoneID.ownerName
      self.assets = assets
      self.record = record
    }
    package init(recordID: CKRecord.ID) {
      self.init(recordID: recordID, assets: [:], record: nil)
    }
    package init(record: CKRecord) {
      do {
        @Dependency(\.dataManager) var dataManager
        let assets = try Dictionary(
          uniqueKeysWithValues: record.allKeys().compactMap { key -> (String, Data)? in
            guard
              let asset = record[key] as? CKAsset,
              let fileURL = asset.fileURL
                else { return nil }
            return (key, try dataManager.load(fileURL))
          }
        )

        self.init(
          recordID: record.recordID,
          assets: assets,
          record: record
        )
      } catch {
        self.init(recordID: record.recordID)
      }
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
        #sql("(\($0.recordName), \($0.zoneName), \($0.ownerName)) IN (\(condition))")
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
