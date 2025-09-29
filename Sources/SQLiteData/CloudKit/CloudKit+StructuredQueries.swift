#if canImport(CloudKit)
  import CloudKit
  import CryptoKit
  import StructuredQueriesCore

  extension _CKRecord where Self == CKRecord {
    public typealias _AllFieldsRepresentation = SQLiteData._AllFieldsRepresentation<CKRecord>
    public typealias SystemFieldsRepresentation = _SystemFieldsRepresentation<CKRecord>
  }

  extension _CKRecord where Self == CKShare {
    public typealias _AllFieldsRepresentation = SQLiteData._AllFieldsRepresentation<CKRecord>
    public typealias SystemFieldsRepresentation = _SystemFieldsRepresentation<CKRecord>
  }

  extension Optional where Wrapped: CKRecord {
    public typealias _AllFieldsRepresentation = SQLiteData._AllFieldsRepresentation<Wrapped>?
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

    public init?(queryBinding: QueryBinding) {
      guard case .blob(let bytes) = queryBinding else { return nil }
      try? self.init(data: Data(bytes))
    }

    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      try self.init(data: try Data(decoder: &decoder))
    }

    private init(data: Data) throws {
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      guard let queryOutput = Record(coder: coder) else {
        throw DecodingError()
      }
      if isTesting {
        queryOutput._recordChangeTag =
          coder
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

    public init?(queryBinding: QueryBinding) {
      guard case .blob(let bytes) = queryBinding else { return nil }
      try? self.init(data: Data(bytes))
    }

    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      try self.init(data: try Data(decoder: &decoder))
    }

    private init(data: Data) throws {
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      guard let queryOutput = Record(coder: coder) else {
        throw DecodingError()
      }
      if isTesting {
        queryOutput._recordChangeTag =
          coder
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
      public init?(queryBinding: QueryBinding) {
        guard case .int(let rawValue) = queryBinding else { return nil }
        try? self.init(rawValue: Int(rawValue))
      }
      public init(decoder: inout some QueryDecoder) throws {
        try self.init(rawValue: Int(decoder: &decoder))
      }
      private init(rawValue: Int) throws {
        guard let queryOutput = CKDatabase.Scope(rawValue: rawValue) else {
          throw DecodingError()
        }
        self.init(queryOutput: queryOutput)
      }
      private struct DecodingError: Error {}
    }
  }

  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  extension CKRecordKeyValueSetting {
    subscript(at key: String) -> Int64 {
      get {
        self["\(CKRecord.userModificationTimeKey)_\(key)"] as? Int64 ?? -1
      }
      set {
        self["\(CKRecord.userModificationTimeKey)_\(key)"] = max(self[at: key], newValue)
      }
    }
  }

  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  extension URL {
    init(hash data: some DataProtocol) {
      // TODO: pass this in explicitly?
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
      at userModificationTime: Int64
    ) -> Bool {
      guard
        encryptedValues[at: key] <= userModificationTime,
        encryptedValues[key] != newValue
      else {
        return false
      }
      encryptedValues[key] = newValue
      encryptedValues[at: key] = userModificationTime
      self.userModificationTime = userModificationTime
      return true
    }

    @discardableResult
    package func setAsset(
      _ newValue: CKAsset,
      forKey key: CKRecord.FieldKey,
      at userModificationTime: Int64
    ) -> Bool {
      guard
        encryptedValues[at: key] <= userModificationTime,
        self[key] != newValue
      else {
        return false
      }
      self[key] = newValue
      encryptedValues[at: key] = userModificationTime
      self.userModificationTime = userModificationTime
      return true
    }

    @discardableResult
    package func setValue(
      _ newValue: [UInt8],
      forKey key: CKRecord.FieldKey,
      at userModificationTime: Int64
    ) -> Bool {
      // TODO: pass this in explicitly?
      @Dependency(\.dataManager) var dataManager

      guard encryptedValues[at: key] <= userModificationTime
      else {
        return false
      }

      let asset = CKAsset(fileURL: URL(hash: newValue))
      guard let fileURL = asset.fileURL, (self[key] as? CKAsset)?.fileURL != fileURL
      else {
        return false
      }
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try dataManager.save(Data(newValue), to: fileURL)
      }
      self[key] = asset
      encryptedValues[at: key] = userModificationTime
      self.userModificationTime = userModificationTime
      return true
    }

    @discardableResult
    package func removeValue(
      forKey key: CKRecord.FieldKey,
      at userModificationTime: Int64
    ) -> Bool {
      guard encryptedValues[at: key] <= userModificationTime
      else {
        return false
      }
      if encryptedValues[key] != nil {
        encryptedValues[key] = nil
        encryptedValues[at: key] = userModificationTime
        self.userModificationTime = userModificationTime
        return true
      } else if self[key] != nil {
        self[key] = nil
        encryptedValues[at: key] = userModificationTime
        self.userModificationTime = userModificationTime
        return true
      }
      return false
    }

    func update<T: PrimaryKeyedTable>(with row: T, userModificationTime: Int64) {
      for column in T.TableColumns.writableColumns {
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
          let keyPath = column.keyPath as! KeyPath<T, Value.QueryOutput>
          let column = column as! any WritableTableColumnExpression<T, Value>
          let value = Value(queryOutput: row[keyPath: keyPath])
          switch value.queryBinding {
          case .blob(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .bool(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .double(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .date(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .int(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .null:
            removeValue(forKey: column.name, at: userModificationTime)
          case .text(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .uint(let value):
            setValue(value, forKey: column.name, at: userModificationTime)
          case .uuid(let value):
            setValue(
              value.uuidString.lowercased(),
              forKey: column.name,
              at: userModificationTime
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

      self.userModificationTime = other.userModificationTime
      for column in T.TableColumns.writableColumns {
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
          let key = column.name
          let keyPath = column.keyPath as! KeyPath<T, Value.QueryOutput>
          let didSet: Bool
          if let value = other[key] as? CKAsset {
            didSet = setAsset(value, forKey: key, at: other.encryptedValues[at: key])
          } else if let value = other.encryptedValues[key] as? any EquatableCKRecordValueProtocol {
            didSet = setValue(value, forKey: key, at: other.encryptedValues[at: key])
          } else if other.encryptedValues[key] == nil {
            didSet = removeValue(forKey: key, at: other.encryptedValues[at: key])
          } else {
            didSet = false
          }
          /// The row value has been modified more recently than the last known record.
          var isRowValueModified: Bool {
            switch Value(queryOutput: row[keyPath: keyPath]).queryBinding {
            case .blob(let value):
              let lhs = (other[key] as? CKAsset)?.fileURL
              let rhs = URL(hash: value)
              let ohs = (self[key] as? CKAsset)?.fileURL
              print(lhs, "!=", rhs)
              return  lhs != rhs
            case .bool(let value):
              return other.encryptedValues[key] != value
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
            case .uint(let value):
              return other.encryptedValues[key] != value
            case .uuid(let value):
              return other.encryptedValues[key] != value.uuidString.lowercased()
            case .invalid(let error):
              reportIssue(error)
              return false
            }
          }
          let _isRowValueModified = isRowValueModified
          if didSet || _isRowValueModified {
            columnNames.removeAll(where: { $0 == key })
            if didSet, let parentForeignKey, key == parentForeignKey.from {
              self.parent = other.parent
            }
          }
        }
        open(column)
      }
    }

    package var userModificationTime: Int64 {
      get { encryptedValues[Self.userModificationTimeKey] as? Int64 ?? -1 }
      set {
        encryptedValues[Self.userModificationTimeKey] = Swift.max(userModificationTime, newValue)
      }
    }

    package static let userModificationTimeKey =
      "\(String.sqliteDataCloudKitSchemaName)_userModificationTime"
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
