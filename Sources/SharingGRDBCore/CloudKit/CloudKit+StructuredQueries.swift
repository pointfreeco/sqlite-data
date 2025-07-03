#if canImport(CloudKit)
import CloudKit
import CryptoKit
import CustomDump
import StructuredQueriesCore

extension _CKRecord where Self == CKRecord {
  typealias AllFieldsRepresentation = _AllFieldsRepresentation<CKRecord>
  public typealias SystemFieldsRepresentation = _SystemFieldsRepresentation<CKRecord>
}

extension _CKRecord where Self == CKShare {
  typealias AllFieldsRepresentation = _AllFieldsRepresentation<CKRecord>
  public typealias SystemFieldsRepresentation = _SystemFieldsRepresentation<CKRecord>
}

extension Optional where Wrapped: CKRecord {
  typealias AllFieldsRepresentation = _AllFieldsRepresentation<Wrapped>?
  public typealias SystemFieldsRepresentation = _SystemFieldsRepresentation<Wrapped>?
}

public struct _SystemFieldsRepresentation<Record: CKRecord>: QueryBindable, QueryRepresentable {
  public let queryOutput: Record

  public var queryBinding: QueryBinding {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    queryOutput.encodeSystemFields(with: archiver)
    if isTesting {
      archiver.encode(queryOutput._recordChangeTag, forKey: "_recordChangeTag")
    }
    return archiver.encodedData.queryBinding
  }

  public init(queryOutput: Record) {
    self.queryOutput = queryOutput
  }

  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    guard let data = try Data?(decoder: &decoder) else {
      throw QueryDecodingError.missingRequiredColumn
    }
    let coder = try NSKeyedUnarchiver(forReadingFrom: data)
    coder.requiresSecureCoding = true
    guard let queryOutput = Record(coder: coder) else {
      throw DecodingError()
    }
    if isTesting {
      queryOutput._recordChangeTag = coder
        .decodeObject(of: NSString.self, forKey: "_recordChangeTag") as? String
    }
    self.init(queryOutput: queryOutput)
  }

  private struct DecodingError: Error {}
}

public struct _AllFieldsRepresentation<Record: CKRecord>: QueryBindable, QueryRepresentable {
  public let queryOutput: Record

  public var queryBinding: QueryBinding {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    queryOutput.encode(with: archiver)
    if isTesting {
      archiver.encode(queryOutput._recordChangeTag, forKey: "_recordChangeTag")
    }
    return archiver.encodedData.queryBinding
  }

  public init(queryOutput: Record) {
    self.queryOutput = queryOutput
  }

  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    guard let data = try Data?(decoder: &decoder) else {
      throw QueryDecodingError.missingRequiredColumn
    }
    let coder = try NSKeyedUnarchiver(forReadingFrom: data)
    coder.requiresSecureCoding = true
    guard let queryOutput = Record(coder: coder) else {
      throw DecodingError()
    }
    if isTesting {
      queryOutput._recordChangeTag = coder
        .decodeObject(of: NSString.self, forKey: "_recordChangeTag") as? String
    }
    self.init(queryOutput: queryOutput)
  }

  private struct DecodingError: Error {}
}

extension CKRecord: _CKRecord {}

public protocol _CKRecord {}

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

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension CKRecordKeyValueSetting {
  subscript(at key: String) -> Date {
    get {
      self["\(CKRecord.userModificationDateKey)_\(key)"] as? Date ?? .distantPast
    }
    set {
      self["\(CKRecord.userModificationDateKey)_\(key)"] = max(self[at: key], newValue)
    }
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension CKRecord {
  @discardableResult
  package func setValue(
    _ newValue: some CKRecordValueProtocol & Equatable,
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    guard
      encryptedValues[at: key] < userModificationDate,
      encryptedValues[key] != newValue
    else { return false }
    encryptedValues[key] = newValue
    encryptedValues[at: key] = userModificationDate
    return true
  }

  @discardableResult
  package func setValue(
    _ newValue: [UInt8],
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    guard encryptedValues[at: key] < userModificationDate else { return false }
    let hash = SHA256.hash(data: newValue).compactMap { String(format: "%02hhx", $0) }.joined()
    let blobURL = URL.temporaryDirectory.appendingPathComponent(hash)
    let asset = CKAsset(fileURL: blobURL)
    if (self[key] as? CKAsset)?.fileURL != blobURL {
      withErrorReporting {
        try Data(newValue).write(to: blobURL)
      }
      self[key] = asset
      encryptedValues[at: key] = userModificationDate
      return true
    }
    return false
  }

  @discardableResult
  package func setValue(
    _ newValue: CKAsset,
    data: @autoclosure () -> [UInt8],
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    guard
      encryptedValues[at: key] < userModificationDate,
      (self[key] as? CKAsset)?.fileURL != newValue.fileURL
    else { return false }
    self[key] = newValue
    encryptedValues[at: key] = userModificationDate
    return true
  }

  @discardableResult
  package func removeValue(
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    guard Swift.max(encryptedValues[at: key], encryptedValues[at: key]) < userModificationDate
    else { return false }
    if encryptedValues[key] != nil {
      encryptedValues[key] = nil
      encryptedValues[at: key] = userModificationDate
      return true
    } else if self[key] != nil {
      self[key] = nil
      encryptedValues[at: key] = userModificationDate
      return true
    }
    return false
  }

  package func update<T: PrimaryKeyedTable>(with row: T, userModificationDate: Date) {
    self.userModificationDate = userModificationDate
    for column in T.TableColumns.allColumns {
      func open<Root, Value>(_ column: some TableColumnExpression<Root, Value>) {
        let column = column as! any TableColumnExpression<T, Value>
        let value = Value(queryOutput: row[keyPath: column.keyPath])
        switch value.queryBinding {
        case .blob(let value):
          setValue(value, forKey: column.name, at: userModificationDate)
        case .double(let value):
          setValue(value, forKey: column.name, at: userModificationDate)
        case .date(let value):
          setValue(value, forKey: column.name, at: userModificationDate)
        case .int(let value):
          setValue(value, forKey: column.name, at: userModificationDate)
        case .null:
          removeValue(forKey: column.name, at: userModificationDate)
        case .text(let value):
          setValue(value, forKey: column.name, at: userModificationDate)
        case .uuid(let value):
          setValue(
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

  func versionedKeys() -> [FieldKey] {
    allKeys()
      .filter { $0.hasPrefix("\(Self.userModificationDateKey)_") }
      .map { String($0.dropFirst("\(Self.userModificationDateKey)_".count)) }
  }

  package func update(with other: CKRecord, columnNames: inout [String]) {
    typealias EquatableCKRecordValueProtocol = CKRecordValueProtocol & Equatable

    self.userModificationDate = other.userModificationDate
    for key in other.versionedKeys() {
      let didSet = if let value = other[key] as? CKAsset {
        setValue(value, forKey: key, at: other.encryptedValues[at: key])
      } else if let value = other.encryptedValues[key] as? any EquatableCKRecordValueProtocol {
        setValue(value, forKey: key, at: other.encryptedValues[at: key])
      } else if other.encryptedValues[key] == nil {
        removeValue(forKey: key, at: other.encryptedValues[at: key])
      } else {
        false
      }
      if didSet {
        columnNames.removeAll(where: { $0 == key })
      }
    }
  }

  package var userModificationDate: Date {
    get { encryptedValues[Self.userModificationDateKey] as? Date ?? .distantPast }
    set {
      encryptedValues[Self.userModificationDateKey] = Swift.max(userModificationDate, newValue)
    }
  }

  fileprivate static let userModificationDateKey =
    "\(String.sqliteDataCloudKitSchemaName)_userModificationDate"
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
