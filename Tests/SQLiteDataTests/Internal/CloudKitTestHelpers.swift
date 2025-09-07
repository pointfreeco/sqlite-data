import CloudKit
import ConcurrencyExtras
import CustomDump
import OrderedCollections
import SQLiteData
import Testing

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable where PrimaryKey.QueryOutput: IdentifierStringConvertible {
  static func recordID(
    for id: PrimaryKey.QueryOutput,
    zoneID: CKRecordZone.ID? = nil
  ) -> CKRecord.ID {
    CKRecord.ID(
      recordName: self.recordName(for: id),
      zoneID: zoneID ?? SyncEngine.defaultTestZone.zoneID
    )
  }
}
