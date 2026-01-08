#if canImport(CloudKit)
  import CloudKit
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
          let keyPath = column.keyPath as! KeyPath<T, Value>

          let clientValue = row[keyPath: keyPath]
          let ancestorValue = ancestorVersion.row[keyPath: keyPath]

          if areEqual(clientValue, ancestorValue) {
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

  private func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    guard
      let lhs = lhs as? any Equatable,
      let rhs = rhs as? any Equatable
    else {
      return false
    }
    
    func open<E: Equatable>(_ lhs: E, _ rhs: Any) -> Bool {
      guard let rhs = rhs as? E else { return false }
      return lhs == rhs
    }
    return open(lhs, rhs)
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
