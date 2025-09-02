#if canImport(CloudKit)
  import CustomDump
  import CloudKit
  import SQLiteData

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

  extension CKRecord {
    @TaskLocal static var printTimestamps = false
  }

  @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
  extension CKRecord: @retroactive CustomDumpReflectable {
    public var customDumpMirror: Mirror {
      let keys = encryptedValues.allKeys()
        .filter { key in
          CKRecord.printTimestamps
            || !key.hasPrefix(CKRecord.userModificationDateKey)
        }
        .sorted { lhs, rhs in
          guard lhs != CKRecord.userModificationDateKey
          else { return false }
          guard rhs != CKRecord.userModificationDateKey
          else { return true }
          let lhsHasPrefix = lhs.hasPrefix(CKRecord.userModificationDateKey)
          let baseLHS =
            lhsHasPrefix
            ? String(lhs.dropFirst(CKRecord.userModificationDateKey.count + 1))
            : lhs
          let rhsHasPrefix = rhs.hasPrefix(CKRecord.userModificationDateKey)
          let baseRHS =
            rhsHasPrefix
            ? String(rhs.dropFirst(CKRecord.userModificationDateKey.count + 1))
            : rhs
          return (baseLHS, lhsHasPrefix ? 1 : 0) < (baseRHS, rhsHasPrefix ? 1 : 0)
        }
      let nonEncryptedKeys = Set(allKeys())
        .subtracting(encryptedValues.allKeys())
        .subtracting(["_recordChangeTag"])
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
            $0.hasPrefix(CKRecord.userModificationDateKey)
              ? (
                String($0.dropFirst(CKRecord.userModificationDateKey.count + 1)) + "🗓️",
                (self.encryptedValues[$0] as? Date).map(\.timeIntervalSince1970).map(Int.init)
                  as Any
              )
              : (
                $0,
                self.encryptedValues[$0] as Any
              )
          }
          + nonEncryptedKeys.map {
            (
              $0,
              self[$0] as Any
            )
          },
        displayStyle: .struct
      )
    }
  }

  extension CKAsset: @retroactive CustomDumpReflectable {
    public var customDumpMirror: Mirror {
      @Dependency(\.dataManager) var dataManager
      return Mirror(
        self,
        children: [
          (
            "fileURL",
            fileURL as Any
          ),
          (
            "dataString",
            String(decoding: fileURL.flatMap { try? dataManager.load($0) } ?? Data(), as: UTF8.self)
          ),
        ],
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
      \(recordName)/\
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
