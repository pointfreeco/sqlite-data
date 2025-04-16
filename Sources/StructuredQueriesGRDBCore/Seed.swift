import Dependencies
import GRDB
import StructuredQueriesCore

extension Database {
  // TODO: docs
  public func seed(
    @InsertValuesBuilder<any StructuredQueriesCore.Table>
    _ build: () -> [any StructuredQueriesCore.Table]
  ) throws {
    var seeds = build()
    while !seeds.isEmpty {
      guard let first = seeds.first else { break }
      let firstType = type(of: first)

      if let firstType = firstType as? any TableDraft.Type {
        func insertBatch<T: TableDraft>(_: T.Type) throws {
          let batch = Array(seeds.lazy.prefix { $0 is T }.compactMap { $0 as? T })
          defer { seeds.removeFirst(batch.count) }
          try T.PrimaryTable.insert(batch).execute(self)
        }

        try insertBatch(firstType)
      } else {
        func insertBatch<T: StructuredQueriesCore.Table>(_: T.Type) throws {
          let batch = Array(seeds.lazy.prefix { $0 is T }.compactMap { $0 as? T })
          defer { seeds.removeFirst(batch.count) }
          try T.insert(batch).execute(self)
        }

        try insertBatch(firstType)
      }
    }
  }
}
