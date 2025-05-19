import CloudKit
import StructuredQueriesCore

extension CKRecord {
  struct DataRepresentation: QueryBindable, QueryRepresentable {
    let queryOutput: CKRecord

    var queryBinding: QueryBinding {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      queryOutput.encodeSystemFields(with: archiver)
      return archiver.encodedData.queryBinding
    }

    init(queryOutput: CKRecord) {
      self.queryOutput = queryOutput
    }

    init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
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

extension CKRecord? {
  typealias DataRepresentation = CKRecord.DataRepresentation?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKRecord {
  static func `for`<T: PrimaryKeyedTable & Sendable>(_ row: T) -> CKRecord? {
    @Dependency(\.defaultSyncEngine) var defaultSyncEngine
    guard let metadatabase = try? DatabasePool(container: defaultSyncEngine.container)
    else { return nil }
    let record =
      withErrorReporting {
        try metadatabase.read { db in
          try Metadata
            .where {
              $0.zoneName.eq(T.tableName)
                && $0.recordName.eq(
                  SQLQueryExpression(
                    T.TableColumns.PrimaryKey(
                      queryOutput: row[keyPath: T.columns.primaryKey.keyPath]
                    )
                    .queryFragment
                  )
                )
            }
            .select(\.lastKnownServerRecord)
            .fetchOne(db)
        }
      }
      ?? nil
    guard let record else { return nil }
    return record
  }
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
          encryptedValues[column.name] = Data(value)
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

  var userModificationDate: Date? {
    get { encryptedValues[Self.userModificationDateKey] as? Date }
    set { encryptedValues[Self.userModificationDateKey] = newValue }
  }

  private static let userModificationDateKey = "sharing_grdb_cloudkit_userModificationDate"
}

extension PrimaryKeyedTable {
  static func find(recordID: CKRecord.ID) -> Where<Self> {
    Self.where {
      SQLQueryExpression("\($0.primaryKey) = \(bind: recordID.recordName)")
    }
  }
}
