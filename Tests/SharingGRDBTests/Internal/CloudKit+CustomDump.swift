#if canImport(CloudKit)
  import CustomDump
  import CloudKit
  import SharingGRDB

  extension CKDatabase.Scope: @retroactive CustomDumpStringConvertible {
    public var customDumpDescription: String {
      switch self {
      case .public:
        ".public"
      case .private:
        ".private"
      case .shared:
        ".shared"
      @unknown default:
        "@unknown"
      }
    }
  }

  @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
  extension CKRecord: @retroactive CustomDumpReflectable {
    public var customDumpMirror: Mirror {
      let keys = encryptedValues.allKeys()
        .sorted { lhs, rhs in
          (
            lhs.hasPrefix("\(String.sqliteDataCloudKitSchemaName)_userModificationDate") ? 1 : 0,
            lhs
          ) < (
            rhs.hasPrefix("\(String.sqliteDataCloudKitSchemaName)_userModificationDate") ? 1 : 0,
            rhs
          )
        }
      return Mirror(
        self,
        children: [
          ("recordID", recordID as Any),
          ("recordType", recordType as Any),
          ("parent", parent as Any),
          ("share", share as Any),
        ]
          + keys
          .map {
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
          ("recordID", recordID as Any)
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
          (
            "recordIDsToDelete",
            recordIDsToDelete.sorted { lhs, rhs in
              lhs.recordName < rhs.recordName
            } as Any
          ),
          (
            "recordsToSave",
            recordsToSave.sorted { lhs, rhs in
              lhs.recordID.recordName < rhs.recordID.recordName
            } as Any
          ),
        ],
        displayStyle: .struct
      )
    }
  }

  extension CKRecord.ID: @retroactive CustomDumpStringConvertible {
    public var customDumpDescription: String {
      """
      CKRecord.ID(\
      \(recordName.replacingOccurrences(of: "^[0-]+", with: "", options: .regularExpression))/\
      \(zoneID.zoneName)/\
      \(zoneID.ownerName)\
      )
      """
    }
  }

  extension CKRecordZone.ID: @retroactive CustomDumpStringConvertible {
    public var customDumpDescription: String {
      "CKRecordZone.ID(\(zoneName)/\(ownerName))"
    }
  }
#endif
