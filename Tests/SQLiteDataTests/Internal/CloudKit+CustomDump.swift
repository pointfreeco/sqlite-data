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
            || !key.hasPrefix(CKRecord.userModificationTimeKey)
        }
        .sorted { lhs, rhs in
          guard lhs != CKRecord.userModificationTimeKey
          else { return false }
          guard rhs != CKRecord.userModificationTimeKey
          else { return true }
          let lhsHasPrefix = lhs.hasPrefix(CKRecord.userModificationTimeKey)
          let baseLHS =
            lhsHasPrefix
            ? String(lhs.dropFirst(CKRecord.userModificationTimeKey.count + 1))
            : lhs
          let rhsHasPrefix = rhs.hasPrefix(CKRecord.userModificationTimeKey)
          let baseRHS =
            rhsHasPrefix
            ? String(rhs.dropFirst(CKRecord.userModificationTimeKey.count + 1))
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
            $0.hasPrefix(CKRecord.userModificationTimeKey)
              ? (
                String($0.dropFirst(CKRecord.userModificationTimeKey.count + 1)) + "🗓️",
                (self.encryptedValues[$0] as? Int64) as Any
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension MockSyncEngineState: CustomDumpReflectable {
    package var customDumpMirror: Mirror {
      return Mirror(
        self,
        children: [
          (
            "pendingRecordZoneChanges",
            _pendingRecordZoneChanges.withValue(\.self)
              .sorted(by: comparePendingRecordZoneChange)
              as Any
          ),
          (
            "pendingDatabaseChanges",
            _pendingDatabaseChanges.withValue(\.self)
              .sorted(by: comparePendingDatabaseChange) as Any
          ),
        ],
        displayStyle: .struct
      )
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func comparePendingRecordZoneChange(
    _ lhs: CKSyncEngine.PendingRecordZoneChange,
    _ rhs: CKSyncEngine.PendingRecordZoneChange
  ) -> Bool {
    switch (lhs, rhs) {
    case (.saveRecord(let lhs), .saveRecord(let rhs)),
      (.deleteRecord(let lhs), .deleteRecord(let rhs)):
      lhs.recordName < rhs.recordName
    case (.deleteRecord, .saveRecord):
      true
    case (.saveRecord, .deleteRecord):
      false
    default:
      false
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func comparePendingDatabaseChange(
    _ lhs: CKSyncEngine.PendingDatabaseChange,
    _ rhs: CKSyncEngine.PendingDatabaseChange
  ) -> Bool {
    switch (lhs, rhs) {
    case (.saveZone(let lhs), .saveZone(let rhs)):
      lhs.zoneID.zoneName < rhs.zoneID.zoneName
    case (.deleteZone(let lhs), .deleteZone(let rhs)):
      lhs.zoneName < rhs.zoneName
    case (.deleteZone, .saveZone):
      true
    case (.saveZone, .deleteZone):
      false
    default:
      false
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension MockCloudContainer: CustomDumpReflectable {
    package var customDumpMirror: Mirror {
      Mirror(
        self,
        children: [
          ("privateCloudDatabase", privateCloudDatabase),
          ("sharedCloudDatabase", sharedCloudDatabase),
        ],
        displayStyle: .struct
      )
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension MockCloudDatabase: CustomDumpReflectable {
    package var customDumpMirror: Mirror {
      Mirror(
        self,
        children: [
          "databaseScope": databaseScope,
          "storage": storage
            .value
            .flatMap { _, value in value.values }
            .sorted {
              ($0.recordType, $0.recordID.recordName) < ($1.recordType, $1.recordID.recordName)
            },
        ],
        displayStyle: .struct
      )
    }
  }

  extension RecordType: CustomDumpReflectable {
    package var customDumpMirror: Mirror {
      Mirror(
        self,
        children: [
          ("tableName", tableName as Any),
          ("schema", schema),
          ("tableInfo", tableInfo.sorted(by: { $0.name < $1.name })),
        ],
        displayStyle: .struct
      )
    }
  }

#endif
