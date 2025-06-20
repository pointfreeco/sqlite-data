import CloudKit
import CustomDump
import StructuredQueriesCore

extension CKRecord {
  public struct DataRepresentation: QueryBindable, QueryRepresentable {
    public let queryOutput: CKRecord

    public var queryBinding: QueryBinding {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      queryOutput.encodeSystemFields(with: archiver)
      return archiver.encodedData.queryBinding
    }

    public init(queryOutput: CKRecord) {
      self.queryOutput = queryOutput
    }

    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      guard let data = try Data?(decoder: &decoder) else {
        throw QueryDecodingError.missingRequiredColumn
      }
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      guard let queryOutput = CKRecord(coder: coder) else {
        throw DecodingError()
      }
      self.init(queryOutput: queryOutput)
    }

    private struct DecodingError: Error {}
  }
}

extension CKShare {
  public struct ShareDataRepresentation: QueryBindable, QueryRepresentable {
    public let queryOutput: CKShare

    public var queryBinding: QueryBinding {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      queryOutput.encodeSystemFields(with: archiver)
      return archiver.encodedData.queryBinding
    }

    public init(queryOutput: CKShare) {
      self.queryOutput = queryOutput
    }

    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      guard let data = try Data?(decoder: &decoder) else {
        throw QueryDecodingError.missingRequiredColumn
      }
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      self.init(queryOutput: CKShare(coder: coder))
    }

    private struct DecodingError: Error {}
  }
}

extension CKRecord? {
  public typealias DataRepresentation = CKRecord.DataRepresentation?
}

extension CKShare? {
  public typealias ShareDataRepresentation = CKShare.ShareDataRepresentation?
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension CKRecord {
  func update<T: PrimaryKeyedTable>(with row: T, userModificationDate: Date?) {
    self.userModificationDate = userModificationDate
    for column in T.TableColumns.allColumns {
      func open<Root, Value>(_ column: some TableColumnExpression<Root, Value>) {
        let column = column as! any TableColumnExpression<T, Value>
        let value = Value(queryOutput: row[keyPath: column.keyPath])
        switch value.queryBinding {
        case .blob(let value):
          let blobURL = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).data")
          withErrorReporting {
            try Data(value).write(to: blobURL)
          }
          self[column.name] = CKAsset(fileURL: blobURL)
        case .double(let value):
          encryptedValues[column.name] = value
        case .date(let value):
          encryptedValues[column.name] = value
        case .int(let value):
          encryptedValues[column.name] = value
        case .null:
          encryptedValues[column.name] = nil
        case .text(let value):
          encryptedValues[column.name] = value
        case .uuid(let value):
          encryptedValues[column.name] = value.uuidString.lowercased()
        case .invalid(let error):
          reportIssue(error)
        }
      }
      open(column)
    }
  }

  package var userModificationDate: Date? {
    get { encryptedValues[Self.userModificationDateKey] as? Date }
    set { encryptedValues[Self.userModificationDateKey] = newValue }
  }

  private static let userModificationDateKey =
    "\(String.sqliteDataCloudKitSchemaName)_userModificationDate"
}

//extension PrimaryKeyedTable where TableColumns.PrimaryKey == UUID {
//  static func find(recordID: CKRecord.ID) -> Where<Self> {
//    let recordName = UUID(uuidString: recordID.recordName)
//    if recordName == nil {
//      reportIssue(
//        """
//        'recordName' ("\(recordID.recordName)") must be a UUID.
//        """
//      )
//    }
//    return Self.where {
//      $0.primaryKey.eq(recordName ?? UUID())
//    }
//  }
//}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  init?(record: CKRecord) {
    let recordName = RecordName(recordID: record.recordID)
    guard let recordName
    else {
      // TODO: is it ok to make this initializer failable?
      return nil
    }
//    if recordName == nil {
//      reportIssue(
//        """
//        'recordName' ("\(record.recordID.recordName)") must be a 'recordType' and UUID pair.
//        """
//      )
//    }
    self.init(
      recordType: record.recordType,
      recordName: recordName,
      lastKnownServerRecord: record,
      userModificationDate: record.userModificationDate
    )
  }
}

extension __CKRecordObjCValue {
  var queryFragment: QueryFragment {
    if let value = self as? Int64 {
      return value.queryFragment
    } else if let value = self as? Double {
      return value.queryFragment
    } else if let value = self as? String {
      return value.queryFragment
    } else if let value = self as? Data {
      return value.queryFragment
    } else if let value = self as? Date {
      return value.queryFragment
    } else {
      return "\(.invalid(Unbindable()))"
    }
  }
}

private struct Unbindable: Error {}

// TODO: Move to custom-dump?
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension CKRecord: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    return Mirror(
      self,
      children: self.allKeys().sorted().map {
        ($0, self[$0] as Any)
      },
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
