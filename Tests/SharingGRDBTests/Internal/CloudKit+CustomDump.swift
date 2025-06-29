import CloudKit
import CustomDump

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension CKRecord: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    return Mirror(
      self,
      children: [
        ("recordID", recordID as Any),
        ("recordType", recordType as Any),
        ("share", share as Any),
        ("parent", parent as Any),
      ] + self.encryptedValues.allKeys().sorted().map {
        ($0, self.encryptedValues[$0] as Any)
      },
      displayStyle: .struct
    )
  }
}

extension CKRecord.Reference: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    return Mirror(
      self,
      children: [
        ("recordID", recordID as Any),
      ],
      displayStyle: .struct
    )
  }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension CKSyncEngine.RecordZoneChangeBatch: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        ("atomicByZone", atomicByZone as Any),
        ("recordIDsToDelete", recordIDsToDelete.sorted { lhs, rhs in
          lhs.recordName < rhs.recordName
        } as Any),
        ("recordsToSave", recordsToSave.sorted { lhs, rhs in
          lhs.recordID.recordName < rhs.recordID.recordName
        } as Any),
      ],
      displayStyle: .struct
    )
  }
}

extension CKRecord.ID: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        "recordName": recordName,
        "zoneID": zoneID,
      ],
      displayStyle: .struct
    )
  }
}

extension CKRecordZone.ID: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        "zoneName": zoneName,
        "ownerName": ownerName,
      ],
      displayStyle: .struct
    )
  }
}
