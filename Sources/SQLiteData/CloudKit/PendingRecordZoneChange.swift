#if canImport(CloudKit)
  import CloudKit

  // @Table("\(String.sqliteDataCloudKitSchemaName)_pendingRecordZoneChanges")
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package struct PendingRecordZoneChange {
    //  @Column(as: CKSyncEngine.PendingRecordZoneChange.DataRepresentation.self)
    package let pendingRecordZoneChange: CKSyncEngine.PendingRecordZoneChange
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PendingRecordZoneChange {
    package init(_ pendingRecordZoneChange: CKSyncEngine.PendingRecordZoneChange) {
      self.pendingRecordZoneChange = pendingRecordZoneChange
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension CKSyncEngine.PendingRecordZoneChange {
    package struct DataRepresentation: QueryBindable, QueryRepresentable {
      package var queryOutput: CKSyncEngine.PendingRecordZoneChange

      package init(queryOutput: CKSyncEngine.PendingRecordZoneChange) {
        self.queryOutput = queryOutput
      }

      package var queryBinding: StructuredQueriesCore.QueryBinding {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        switch queryOutput {
        case .saveRecord(let recordID):
          recordID.encode(with: archiver)
          archiver.encode("saveRecord", forKey: "changeType")
        case .deleteRecord(let recordID):
          recordID.encode(with: archiver)
          archiver.encode("deleteRecord", forKey: "changeType")
        @unknown default:
          return .invalid(BindingError())
        }
        return archiver.encodedData.queryBinding
      }

      package init?(queryBinding: StructuredQueriesCore.QueryBinding) {
        guard case .blob(let bytes) = queryBinding else { return nil }
        try? self.init(data: Data(bytes))
      }

      package init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
        try self.init(data: Data(decoder: &decoder))
      }

      private init(data: Data) throws {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = true
        guard let recordID = CKRecord.ID(coder: coder) else {
          throw DecodingError()
        }
        let changeType = coder.decodeObject(of: NSString.self, forKey: "changeType") as? String
        switch changeType {
        case "saveRecord":
          self.init(queryOutput: .saveRecord(recordID))
        case "deleteRecord":
          self.init(queryOutput: .deleteRecord(recordID))
        default:
          throw DecodingError()
        }
      }
    }

    private struct DecodingError: Error {}
    private struct BindingError: Error {}
  }
#endif
