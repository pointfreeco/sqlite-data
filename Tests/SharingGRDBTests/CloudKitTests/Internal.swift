import CloudKit
import StructuredQueriesCore

extension CKRecord.ID {
  convenience init<T: PrimaryKeyedTable>(
    _ id: T.TableColumns.PrimaryKey,
    in table: T.Type
  )
  where T.TableColumns.PrimaryKey == UUID {
    self.init(
      recordName: id.uuidString.lowercased(),
      zoneID: CKRecordZone.ID(zoneName: T.tableName)
    )
  }
}
