import StructuredQueriesCore

extension StructuredQueriesCore.Statement {
  /// Executes a structured query on the given database connection.
  ///
  /// For example:
  ///
  /// ```swift
  /// try database.write { db in
  ///   try Player.insert { $0.name } values: { "Arthur" }
  ///     .execute(db)
  ///   // INSERT INTO "players" ("name")
  ///   // VALUES ('Arthur');
  /// }
  /// ```
  ///
  /// - Parameter db: A database connection.
  @inlinable
  public func execute(_ db: Database) throws where QueryValue == () {
    try QueryVoidCursor(db: db, query: query).next()
  }

  /// Returns an array of all values fetched from the database.
  ///
  /// For example:
  ///
  /// ```swift
  /// let players = try database.read { db in
  ///   let lastName = "O'Reilly"
  ///   try Player
  ///     .where { $0.lastName == lastName }
  ///     .fetchAll(db)
  ///   // SELECT … FROM "players"
  ///   // WHERE "players"."lastName" = 'O''Reilly'
  /// }
  /// ```
  ///
  /// - Parameter db: A database connection.
  /// - Returns: An array of all values decoded from the database.
  @inlinable
  public func fetchAll(_ db: Database) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    let cursor = try QueryValueCursor<QueryValue>(db: db, query: query)
    var output: [QueryValue.QueryOutput] = []
    try cursor.forEach { output.append($0) }
    return output
  }

  /// Returns a single value fetched from the database.
  ///
  /// For example:
  ///
  /// ```swift
  /// let player = try database.read { db in
  ///   let lastName = "O'Reilly"
  ///   try Player
  ///     .where { $0.lastName == lastName }
  ///     .limit(1)
  ///     .fetchOne(db)
  ///   // SELECT … FROM "players"
  ///   // WHERE "players"."lastName" = 'O''Reilly'
  ///   // LIMIT 1
  /// }
  /// ```
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A single value decoded from the database.
  @inlinable
  public func fetchOne(_ db: Database) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    try fetchCursor(db).next()
  }

  /// Returns a cursor to all values fetched from the database.
  ///
  /// For example:
  ///
  /// ```swift
  /// try database.read { db in
  ///   let lastName = "O'Reilly"
  ///   let query = Player.where { $0.lastName == lastName }
  ///   let players = try query.fetchCursor(db)
  ///   while let player = try players.next() {
  ///     print(player.name)
  ///   }
  /// }
  /// ```
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A cursor to all values decoded from the database.
  @inlinable
  public func fetchCursor(_ db: Database) throws -> QueryCursor<QueryValue.QueryOutput>
  where QueryValue: QueryRepresentable {
    try QueryValueCursor<QueryValue>(db: db, query: query)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension StructuredQueriesCore.Statement {
  /// Returns an array of all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: An array of all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchAll<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try Array(cursor)
  }

  /// Returns a single value fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A single value decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchOne<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try cursor.next()
  }

  /// Returns a cursor to all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A cursor to all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchCursor<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> QueryCursor<(repeat (each Value).QueryOutput)>
  where QueryValue == (repeat each Value) {
    try QueryPackCursor<repeat each Value>(db: db, query: query)
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  /// Returns the number of rows fetched by the query.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: The number of rows fetched by the query.
  @inlinable
  public func fetchCount(_ db: Database) throws -> Int {
    let query = asSelect().count()
    return try query.fetchOne(db) ?? 0
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  /// Returns an array of all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: An array of all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchAll(_ db: Database) throws -> [From.QueryOutput] {
    let cursor = try QueryValueCursor<From>(db: db, query: query)
    var output: [From.QueryOutput] = []
    try cursor.forEach { output.append($0) }
    return output
  }

  /// Returns a single value fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A single value decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchOne(_ db: Database) throws -> From.QueryOutput? {
    try asSelect().limit(1).fetchCursor(db).next()
  }

  /// Returns a cursor to all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A cursor to all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchCursor(_ db: Database) throws -> QueryCursor<From.QueryOutput> {
    try QueryValueCursor<From>(db: db, query: query)
  }
}

extension SelectStatement where QueryValue == (), From: PrimaryKeyedTable, Joins == () {
  /// Returns a single value fetched from the database for a given primary key.
  ///
  /// - Parameters
  ///   - db: A database connection.
  ///   - primaryKey: A primary key identifying a table row.
  /// - Returns: A single value decoded from the database.
  @inlinable
  public func find(
    _ db: Database,
    key primaryKey: some QueryExpression<From.PrimaryKey>
  ) throws -> From.QueryOutput {
    guard let record = try asSelect().find(primaryKey).fetchOne(db) else {
      throw NotFound()
    }
    return record
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SelectStatement where QueryValue == () {
  /// Returns an array of all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: An array of all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchAll<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> [(From.QueryOutput, repeat (each J).QueryOutput)]
  where Joins == (repeat each J) {
    try Array(fetchCursor(db))
  }

  /// Returns a single value fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A single value decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchOne<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> (From.QueryOutput, repeat (each J).QueryOutput)?
  where Joins == (repeat each J) {
    try asSelect().limit(1).fetchCursor(db).next()
  }

  /// Returns a cursor to all values fetched from the database.
  ///
  /// - Parameter db: A database connection.
  /// - Returns: A cursor to all values decoded from the database.
  @_documentation(visibility: private)
  @inlinable
  public func fetchCursor<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> QueryCursor<(From.QueryOutput, repeat (each J).QueryOutput)>
  where Joins == (repeat each J) {
    try QueryPackCursor<From, repeat each J>(db: db, query: query)
  }
}
