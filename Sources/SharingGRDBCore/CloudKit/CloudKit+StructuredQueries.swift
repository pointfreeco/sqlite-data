import CloudKit
import CustomDump
import StructuredQueriesCore

extension CKRecord {
  package struct DataRepresentation: QueryBindable, QueryRepresentable {
    package let queryOutput: CKRecord

    package var queryBinding: QueryBinding {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      queryOutput.encodeSystemFields(with: archiver)
      return archiver.encodedData.queryBinding
    }

    package init(queryOutput: CKRecord) {
      self.queryOutput = queryOutput
    }

    package init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
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
  package typealias DataRepresentation = CKRecord.DataRepresentation?
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

  package var userModificationDate: Date? {
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
