#if canImport(CloudKit)
  import CloudKit
  import CryptoKit
  import Foundation
  import SQLiteData
  import Testing

  struct RowVersion<T: PrimaryKeyedTable> {
    let row: T
    private let modificationTimes: [PartialKeyPath<T>: Int64]

    package init(
      row: T,
      modificationTimes: [PartialKeyPath<T>: Int64]
    ) {
      self.row = row
      self.modificationTimes = modificationTimes
    }

    init(
      clientRow row: T,
      userModificationTime: Int64,
      ancestorVersion: RowVersion<T>
    ) {
      var modificationTimes: [PartialKeyPath<T>: Int64] = [:]
      for column in T.TableColumns.writableColumns {
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
          let keyPath = column.keyPath as! KeyPath<T, Value.QueryOutput>

          let clientValue = row[keyPath: keyPath]
          let ancestorValue = ancestorVersion.row[keyPath: keyPath]

          if areEqual(clientValue, ancestorValue, as: Value.self) {
            modificationTimes[keyPath] = ancestorVersion.modificationTime(for: keyPath)
          } else {
            modificationTimes[keyPath] = userModificationTime
          }
        }
        open(column)
      }
      
      self.init(
        row: row,
        modificationTimes: modificationTimes
      )
    }

    init(from record: CKRecord) throws {
      fatalError("Not implemented")
    }

    func modificationTime(for column: PartialKeyPath<T>) -> Int64 {
      return modificationTimes[column] ?? -1
    }
  }

  struct MergeConflict<T: PrimaryKeyedTable> {
    let ancestor: RowVersion<T>
    let client: RowVersion<T>
    let server: RowVersion<T>
  }

  extension MergeConflict {
    func mergedValue<V: Equatable>(
      for keyPath: some KeyPath<T.TableColumns, V>
    ) -> V {
      fatalError("Not implemented")
    }
  }

  /// Compares values using their database representation (`QueryBinding`), which eliminates
  /// the need for `Equatable` conformance and efficiently handles special cases.
  fileprivate func areEqual<Value: QueryRepresentable & QueryBindable>(
    _ lhs: Value.QueryOutput,
    _ rhs: Value.QueryOutput,
    as: Value.Type
  ) -> Bool {
    let lhsBinding = Value(queryOutput: lhs).queryBinding
    let rhsBinding = Value(queryOutput: rhs).queryBinding

    switch (lhsBinding, rhsBinding) {
    case (.blob(let lhsValue), .blob(let rhsValue)):
      return lhsValue.sha256 == rhsValue.sha256
    case (.bool(let lhsValue), .bool(let rhsValue)):
      return lhsValue == rhsValue
    case (.double(let lhsValue), .double(let rhsValue)):
      return lhsValue == rhsValue
    case (.date(let lhsValue), .date(let rhsValue)):
      return lhsValue == rhsValue
    case (.int(let lhsValue), .int(let rhsValue)):
      return lhsValue == rhsValue
    case (.null, .null):
      return true
    case (.text(let lhsValue), .text(let rhsValue)):
      return lhsValue == rhsValue
    case (.uint(let lhsValue), .uint(let rhsValue)):
      return lhsValue == rhsValue
    case (.uuid(let lhsValue), .uuid(let rhsValue)):
      // TODO: Can't we compare the UUID instances directly?
      return lhsValue.uuidString.lowercased() == rhsValue.uuidString.lowercased()
    case (.invalid(let error), _), (_, .invalid(let error)):
      reportIssue(error)
      return false
    default:
      return false
    }
  }

  extension DataProtocol {
    fileprivate var sha256: Data {
      Data(SHA256.hash(data: self))
    }
  }

  @Table
  private struct Counter {
    let id: UUID
    var title: String
    var count: Int
  }

  @Suite
  struct ConflictResolutionPlaygroundTests {
    @Test
    func init_rowAndModificationTimes() {
      let version = RowVersion(
        row: Counter(id: UUID(0), title: "MyCounter", count: 0),
        modificationTimes: [
          \.title: 100,
          \.count: 0
        ]
      )
      
      #expect(version.modificationTime(for: \.title) == 100)
      #expect(version.modificationTime(for: \.count) == 0)
    }

    @Test
    func init_clientRow() {
      let ancestor = RowVersion(
        row: Counter(id: UUID(0), title: "", count: 0),
        modificationTimes: [
          \.title: 50,
          \.count: 50
        ]
      )

      let client = RowVersion(
        clientRow: Counter(id: UUID(0), title: "My Counter", count: 0),
        userModificationTime: 100,
        ancestorVersion: ancestor
      )

      #expect(client.modificationTime(for: \.title) == 100)
      #expect(client.modificationTime(for: \.count) == 50)
    }
  }
#endif
