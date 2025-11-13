import GRDB

extension GRDB.Database {
  public func bulkInsert<T: StructuredQueries.Table>(_ rows: [T]) throws {
    guard let sampleValue = rows.first
    else { return }
    let query = T.insert { [sampleValue] }
    let statement = try makeStatement(
      sql: query.query.prepare { _ in "?" }.sql
    )
    for row in rows {
      let arguments = T.TableColumns.writableColumns.map { column in
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) -> any DatabaseValueConvertible {
          let keyPath = column.keyPath as! KeyPath<T, Value.QueryOutput>
          return row[keyPath: keyPath] as! any DatabaseValueConvertible
        }

        return open(column)
      }
      statement.setUncheckedArguments(StatementArguments(arguments))
      try statement.execute()
    }
  }
}
