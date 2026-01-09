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
    func mergedValue<Column: WritableTableColumnExpression>(
      for keyPath: some KeyPath<T.TableColumns, Column>
    ) -> Column.QueryValue.QueryOutput
    where Column.Root == T {
      let column = T.columns[keyPath: keyPath]
      let rowKeyPath = column.keyPath

      let ancestorValue = ancestor.row[keyPath: rowKeyPath]
      let clientValue = client.row[keyPath: rowKeyPath]
      let serverValue = server.row[keyPath: rowKeyPath]

      let clientChanged = !areEqual(ancestorValue, clientValue, as: Column.QueryValue.self)
      let serverChanged = !areEqual(ancestorValue, serverValue, as: Column.QueryValue.self)

      switch (clientChanged, serverChanged) {
      case (false, false):
        return clientValue
      case (true, false):
        return clientValue
      case (false, true):
        return serverValue
      case (true, true):
        if areEqual(clientValue, serverValue, as: Column.QueryValue.self) {
          return clientValue
        }

        let clientTime = client.modificationTime(for: rowKeyPath)
        let serverTime = server.modificationTime(for: rowKeyPath)
        return serverTime > clientTime ? serverValue : clientValue
      }
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

  @Table
  private struct MergeExample {
    let id: UUID
    var field1: String
    var field2: String
    var field3: String
    var field4: String
    var field5: String
    var field6: String
    var field7: String
  }

  @Suite
  struct ConflictResolutionPlaygroundTests {
    @Test
    func versionInit_rowAndModificationTimes() {
      let version = RowVersion(
        row: Counter(id: UUID(0), title: "My Counter", count: 0),
        modificationTimes: [
          \.title: 100,
          \.count: 0
        ]
      )
      
      #expect(version.modificationTime(for: \.title) == 100)
      #expect(version.modificationTime(for: \.count) == 0)
    }

    @Test
    func versionInit_clientRow() {
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

    /// Tests the field-wise last edit wins strategy with all seven merge scenarios.
    /// See: https://github.com/structuredpath/sqlite-data-sync-notes/blob/main/BuiltInConflictResolutionModel.md
    @Test
    func mergeConflict_fieldWiseLastEditWins() {
      let ancestor = RowVersion(
        row: MergeExample(
          id: UUID(0),
          field1: "foo",
          field2: "foo",
          field3: "foo",
          field4: "foo",
          field5: "foo",
          field6: "foo",
          field7: "foo"
        ),
        modificationTimes: [
          \.field1: 0,
          \.field2: 0,
          \.field3: 0,
          \.field4: 0,
          \.field5: 0,
          \.field6: 0,
          \.field7: 0
        ]
      )

      let client = RowVersion(
        row: MergeExample(
          id: UUID(0),
          field1: "foo",
          field2: "bar",
          field3: "foo",
          field4: "bar",
          field5: "bar",
          field6: "bar",
          field7: "bar"
        ),
        modificationTimes: [
          \.field1: 0,
          \.field2: 100,
          \.field3: 0,
          \.field4: 100,
          \.field5: 100,
          \.field6: 100,
          \.field7: 100
        ]
      )

      let server = RowVersion(
        row: MergeExample(
          id: UUID(0),
          field1: "foo",
          field2: "foo",
          field3: "baz",
          field4: "baz",
          field5: "baz",
          field6: "baz",
          field7: "bar"
        ),
        modificationTimes: [
          \.field1: 0,
          \.field2: 0,
          \.field3: 200,
          \.field4: 200,
          \.field5: 50,
          \.field6: 100,
          \.field7: 200
        ]
      )

      let conflict = MergeConflict(
        ancestor: ancestor,
        client: client,
        server: server
      )

      #expect(conflict.mergedValue(for: \.field1) == "foo")
      #expect(conflict.mergedValue(for: \.field2) == "bar")
      #expect(conflict.mergedValue(for: \.field3) == "baz")
      #expect(conflict.mergedValue(for: \.field4) == "baz")
      #expect(conflict.mergedValue(for: \.field5) == "bar")
      #expect(conflict.mergedValue(for: \.field6) == "bar")
      #expect(conflict.mergedValue(for: \.field7) == "bar")
    }
  }
#endif
