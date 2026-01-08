#if canImport(CloudKit)
  import CloudKit
  import Foundation
  import SQLiteData
  import Testing

  struct RowVersion<T: PrimaryKeyedTable> {
    let row: T
    
    init(
      clientRow row: T,
      userModificationTime: Int64,
      ancestorVersion: RowVersion<T>
    ) {
      self.row = row
      fatalError("Not implemented")
    }

    init(from record: CKRecord) throws {
      fatalError("Not implemented")
    }

    func modificationDate(for column: PartialKeyPath<T.TableColumns>) -> Int64 {
      fatalError("Not implemented")
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

  @Table
  private struct Counter {
    let id: Int
    var title: String
    var count: Int
  }

  @Suite
  struct ConflictResolutionPlaygroundTests {
    @Test
    func placeholder() {
    }
  }
#endif
