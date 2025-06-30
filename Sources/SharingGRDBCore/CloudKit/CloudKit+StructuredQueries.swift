#if canImport(CloudKit)
import CloudKit
import CryptoKit
import CustomDump
import StructuredQueriesCore

extension CKRecord {
  public struct DataRepresentation: QueryBindable, QueryRepresentable {
    public let queryOutput: CKRecord

    public var queryBinding: QueryBinding {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      queryOutput.encodeSystemFields(with: archiver)
      if isTesting {
        archiver.encode(queryOutput._recordChangeTag, forKey: "_recordChangeTag")
      }
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
      if isTesting {
        queryOutput._recordChangeTag = coder
          .decodeObject(of: NSString.self, forKey: "_recordChangeTag")
        as? String
      }
      self.init(queryOutput: queryOutput)
    }

    private struct DecodingError: Error {}
  }
}

extension CKShare {
  // TODO: Confirm that it's not possible to name this 'DataRepresentation'
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

extension CKDatabase.Scope {
  public struct RawValueRepresentation: QueryBindable, QueryRepresentable {
    public let queryOutput: CKDatabase.Scope
    public var queryBinding: QueryBinding {
      queryOutput.rawValue.queryBinding
    }
    public init(queryOutput: CKDatabase.Scope) {
      self.queryOutput = queryOutput
    }
    public init(decoder: inout some QueryDecoder) throws {
      guard
        let rawValue = try Int?(decoder: &decoder),
        let scope = CKDatabase.Scope(rawValue: rawValue)
      else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.init(queryOutput: scope)
    }
  }
}

extension CKRecordKeyValueSetting {
  package func setValue(
    _ newValue: some CKRecordValueProtocol & Equatable,
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date?
  ) {
    if self[key] != newValue {
      self[key] = newValue
      self[
        "\(String.sqliteDataCloudKitSchemaName)_userModificationDate_\(key)"
      ] = userModificationDate
    }
  }

  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  package func setValue(
    _ newValue: [UInt8],
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date?
  ) {
    let hash = SHA256.hash(data: newValue).compactMap { String(format: "%02hhx", $0) }.joined()
    let blobURL = URL.temporaryDirectory.appendingPathComponent(hash)
    let asset = CKAsset(fileURL: blobURL)
    if (self[key] as? CKAsset)?.fileURL != blobURL {
      withErrorReporting {
        try Data(newValue).write(to: blobURL)
      }
      self[key] = asset
      self[
        "\(String.sqliteDataCloudKitSchemaName)_userModificationDate_\(key)"
      ] = userModificationDate
    }
  }

  package func removeValue(
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date?
  ) {
    if self[key] != nil {
      self[key] = nil
      self[
        "\(String.sqliteDataCloudKitSchemaName)_userModificationDate_\(key)"
      ] = userModificationDate
    }
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension CKRecord {
  package func update<T: PrimaryKeyedTable>(with row: T, userModificationDate: Date?) {
    self.userModificationDate = userModificationDate
    for column in T.TableColumns.allColumns {
      func open<Root, Value>(_ column: some TableColumnExpression<Root, Value>) {
        let column = column as! any TableColumnExpression<T, Value>
        let value = Value(queryOutput: row[keyPath: column.keyPath])
        switch value.queryBinding {
        case .blob(let value):
          encryptedValues.setValue(value, forKey: column.name, at: userModificationDate)
        case .double(let value):
          encryptedValues.setValue(value, forKey: column.name, at: userModificationDate)
        case .date(let value):
          encryptedValues.setValue(value, forKey: column.name, at: userModificationDate)
        case .int(let value):
          encryptedValues.setValue(value, forKey: column.name, at: userModificationDate)
        case .null:
          encryptedValues.removeValue(forKey: column.name, at: userModificationDate)
        case .text(let value):
          encryptedValues.setValue(value, forKey: column.name, at: userModificationDate)
        case .uuid(let value):
          encryptedValues.setValue(
            value.uuidString.lowercased(),
            forKey: column.name,
            at: userModificationDate
          )
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

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  init?(record: CKRecord) {
    let recordName = RecordName(recordID: record.recordID)
    guard let recordName
    else { return nil }
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

extension CKRecord {
  package var _recordChangeTag: String? {
    get { self[#function] }
    set { self[#function] = newValue }
  }
}
#endif
