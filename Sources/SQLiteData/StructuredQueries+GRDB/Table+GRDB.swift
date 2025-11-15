import StructuredQueriesCore

extension StructuredQueriesCore.Table {
  /// Returns an array of all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: An array of all values decoded from the database.
  @inlinable
  public static func fetchAll(_ db: Database) throws -> [QueryOutput] {
    try all.fetchAll(db)
  }

  /// Returns a single value fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A single value decoded from the database.
  @inlinable
  public static func fetchOne(_ db: Database) throws -> QueryOutput? {
    try all.fetchOne(db)
  }

  /// Returns the number of rows fetched by the query.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: The number of rows fetched by the query.
  @inlinable
  public static func fetchCount(_ db: Database) throws -> Int {
    try all.fetchCount(db)
  }

  /// Returns a cursor to all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A cursor to all values decoded from the database.
  @inlinable
  public static func fetchCursor(_ db: Database) throws -> QueryCursor<QueryOutput> {
    try all.fetchCursor(db)
  }
}

extension StructuredQueriesCore.PrimaryKeyedTable {
  /// Returns a single value fetched from the database for a given primary key.
  ///
  /// - Parameters
  ///   - db: A database connection.
  ///   - primaryKey: A primary key identifying a table row.
  /// - Returns: A single value decoded from the database.
  @inlinable
  public static func find(
    _ db: Database,
    key primaryKey: some QueryExpression<PrimaryKey>
  ) throws -> QueryOutput {
    try all.find(db, key: primaryKey)
  }
}
