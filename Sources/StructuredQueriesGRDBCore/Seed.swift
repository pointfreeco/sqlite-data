import Dependencies
import GRDB
import StructuredQueriesCore

extension Database {
  // TODO: docs
  public func seed(
    @InsertValuesBuilder<any StructuredQueriesCore.Table>
    _ build: () -> [any StructuredQueriesCore.Table]
  ) throws {
    func open<T: StructuredQueriesCore.Table>(_ seed: T) throws {
      if let seed = seed as? any TableDraft {
        func open<Draft: TableDraft>(_ seed: Draft) throws {
          try Draft.PrimaryTable.insert(seed)
            .execute(self)
        }
        try open(seed)
      } else {
        try T.insert(seed).execute(self)
      }
    }

    for seed in build() {
      try open(seed)
    }
  }
}
