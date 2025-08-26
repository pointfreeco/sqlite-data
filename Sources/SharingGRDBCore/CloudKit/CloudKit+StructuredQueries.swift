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
  package typealias AllFieldsRepresentation = _AllFieldsRepresentation<Wrapped>?
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

package struct _AllFieldsRepresentation<Record: CKRecord>: QueryBindable, QueryRepresentable {
  package let queryOutput: Record

  package var queryBinding: QueryBinding {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    queryOutput.encode(with: archiver)
    if isTesting {
      archiver.encode(queryOutput._recordChangeTag, forKey: "_recordChangeTag")
    }
    return archiver.encodedData.queryBinding
  }

  package init(queryOutput: Record) {
    self.queryOutput = queryOutput
  }

  package init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
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
extension URL {
  init(hash data: some DataProtocol) {
    @Dependency(\.dataManager) var dataManager
    let hash = SHA256.hash(data: data).compactMap { String(format: "%02hhx", $0) }.joined()
    self = dataManager.temporaryDirectory.appendingPathComponent(hash)
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
    self.userModificationDate = userModificationDate
    return true
  }

  @discardableResult
  package func setValue(
    _ newValue: [UInt8],
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    @Dependency(\.dataManager) var dataManager

    guard encryptedValues[at: key] < userModificationDate else { return false }

    let asset = CKAsset(fileURL: URL(hash: newValue))
    guard let fileURL = asset.fileURL, (self[key] as? CKAsset)?.fileURL != fileURL
    else { return false }
    withErrorReporting {
      try dataManager.save(Data(newValue), to: fileURL)
    }
    self[key] = asset
    encryptedValues[at: key] = userModificationDate
    self.userModificationDate = userModificationDate
    return true
  }

  @discardableResult
  package func removeValue(
    forKey key: CKRecord.FieldKey,
    at userModificationDate: Date
  ) -> Bool {
    guard encryptedValues[at: key] < userModificationDate
    else { return false }
    if encryptedValues[key] != nil {
      encryptedValues[key] = nil
      encryptedValues[at: key] = userModificationDate
      self.userModificationDate = userModificationDate
      return true
    } else if self[key] != nil {
      self[key] = nil
      encryptedValues[at: key] = userModificationDate
      self.userModificationDate = userModificationDate
      return true
    }
    return false
  }

  func update<T: PrimaryKeyedTable>(with row: T, userModificationDate: Date) {
    for column in T.TableColumns.writableColumns {
      func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
        let column = column as! any WritableTableColumnExpression<T, Value>
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

  func update<T: PrimaryKeyedTable>(
    with other: CKRecord,
    row: T,
    columnNames: inout [String],
    parentForeignKey: ForeignKey?
  ) {
    typealias EquatableCKRecordValueProtocol = CKRecordValueProtocol & Equatable

    self.userModificationDate = other.userModificationDate
    for column in T.TableColumns.writableColumns {
      func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
        let key = column.name
        let column = column as! any WritableTableColumnExpression<T, Value>
        let didSet: Bool
        if let value = other[key] as? CKAsset {
          didSet = setValue(value, forKey: key, at: other[at: key])
        } else if let value = other.encryptedValues[key] as? any EquatableCKRecordValueProtocol {
          didSet = setValue(value, forKey: key, at: other.encryptedValues[at: key])
        } else if other.encryptedValues[key] == nil {
          didSet = removeValue(forKey: key, at: other.encryptedValues[at: key])
        } else {
          didSet = false
        }
        /// The row value has been modified more recently than the last known record.
        var isRowValueModified: Bool {
          switch Value(queryOutput: row[keyPath: column.keyPath]).queryBinding {
          case .blob(let value):
            return (other[key] as? CKAsset)?.fileURL != URL(hash: value)
          case .double(let value):
            return other.encryptedValues[key] != value
          case .date(let value):
            return other.encryptedValues[key] != value
          case .int(let value):
            return other.encryptedValues[key] != value
          case .null:
            return other.encryptedValues[key] != nil
          case .text(let value):
            return other.encryptedValues[key] != value
          case .uuid(let value):
            return other.encryptedValues[key] != value.uuidString.lowercased()
          case .invalid(let error):
            reportIssue(error)
            return false
          }
        }
        if didSet || isRowValueModified {
          columnNames.removeAll(where: { $0 == key })
          if didSet, let parentForeignKey, key == parentForeignKey.from {
            self.parent = other.parent
          }
        }
      }
      open(column)
    }
  }

  package var userModificationDate: Date {
    get { encryptedValues[Self.userModificationDateKey] as? Date ?? .distantPast }
    set {
      encryptedValues[Self.userModificationDateKey] = Swift.max(userModificationDate, newValue)
    }
  }

  package static let userModificationDateKey =
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
