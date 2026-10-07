public import GRDB
public import StructuredQueriesCore

extension SelectStatement where QueryValue == (), Joins == () {
  /// Returns all values fetched from the database, grouped into sections.
  ///
  /// Results are ordered by the given expression and grouped into a section for each of its
  /// distinct values:
  ///
  /// ```swift
  /// try Reminder
  ///   .order(by: \.title)
  ///   .fetchAll(db, sectionBy: \.priority)
  /// ```
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - sectioning: A closure that returns an expression, or an ordering of one, to group results
  ///     by.
  /// - Returns: A collection of all values decoded from the database, grouped into sections.
  public func fetchAll<Key: QueryRepresentable>(
    _ db: Database,
    @_SectionBuilder<Key> sectionBy sectioning: (From.TableColumns) -> _Sectioning<Key>
  ) throws -> ResultsSectionCollection<From.QueryOutput, Key.QueryOutput>
  where Key.QueryOutput: Hashable {
    let sectionBy = sectioning(From.columns)
    let statement: Select<(), From, ()> = asSelect()
    let prefix: Select<(From, Key), From, ()> = sectionedColumns(of: From.self, sectionBy)
    let sectioned: Select<(From, Key), From, ()> = prefix + statement
    return try sectionedResults(From.self, Key.self, db: db, query: sectioned.query)
  }

  /// Returns all values fetched from the database, grouped into sections.
  ///
  /// See ``StructuredQueriesCore/SelectStatement/fetchAll(_:sectionBy:)`` for more information.
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - sectionKeyPath: A key path to a column to group results by.
  /// - Returns: A collection of all values decoded from the database, grouped into sections.
  public func fetchAll<Key: QueryRepresentable>(
    _ db: Database,
    sectionBy sectionKeyPath: KeyPath<
      From.TableColumns, some QueryExpression<Key>
    >
  ) throws -> ResultsSectionCollection<From.QueryOutput, Key.QueryOutput>
  where Key.QueryOutput: Hashable {
    try fetchAll(db, sectionBy: { $0[keyPath: sectionKeyPath] })
  }
}

extension Select where From: StructuredQueriesCore.Table {
  /// Returns all values fetched from the database, grouped into sections.
  ///
  /// See ``StructuredQueriesCore/SelectStatement/fetchAll(_:sectionBy:)`` for more information.
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - sectioning: A closure that returns an expression, or an ordering of one, to group results
  ///     by.
  /// - Returns: A collection of all values decoded from the database, grouped into sections.
  @_documentation(visibility: private)
  @_disfavoredOverload
  public func fetchAll<Key: QueryRepresentable, each J: StructuredQueriesCore.Table>(
    _ db: Database,
    @_SectionBuilder<Key> sectionBy sectioning: (
      From.TableColumns, repeat (each J).TableColumns
    ) -> _Sectioning<Key>
  ) throws -> ResultsSectionCollection<QueryValue.QueryOutput, Key.QueryOutput>
  where QueryValue: QueryRepresentable, Joins == (repeat each J), Key.QueryOutput: Hashable {
    let sectionBy = sectioning(From.columns, repeat (each J).columns)
    return try sectionedResults(db, statement: self, sectionBy: sectionBy)
  }

  /// Returns all values fetched from the database, grouped into sections.
  ///
  /// See ``StructuredQueriesCore/SelectStatement/fetchAll(_:sectionBy:)`` for more information.
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - sectioning: A closure that returns an expression, or an ordering of one, to group results
  ///     by.
  /// - Returns: A collection of all values decoded from the database, grouped into sections.
  @_documentation(visibility: private)
  public func fetchAll<Key: QueryRepresentable>(
    _ db: Database,
    @_SectionBuilder<Key> sectionBy sectioning: (
      From.TableColumns, Joins.TableColumns
    ) -> _Sectioning<Key>
  ) throws -> ResultsSectionCollection<QueryValue.QueryOutput, Key.QueryOutput>
  where
    QueryValue: QueryRepresentable,
    Joins: StructuredQueriesCore.Table,
    Key.QueryOutput: Hashable
  {
    let sectionBy = sectioning(From.columns, Joins.columns)
    return try sectionedResults(db, statement: self, sectionBy: sectionBy)
  }

  /// Returns all values fetched from the database, grouped into sections.
  ///
  /// See ``StructuredQueriesCore/SelectStatement/fetchAll(_:sectionBy:)`` for more information.
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - sectionKeyPath: A key path to a column to group results by.
  /// - Returns: A collection of all values decoded from the database, grouped into sections.
  public func fetchAll<Key: QueryRepresentable>(
    _ db: Database,
    sectionBy sectionKeyPath: KeyPath<
      From.TableColumns, some QueryExpression<Key>
    >
  ) throws -> ResultsSectionCollection<QueryValue.QueryOutput, Key.QueryOutput>
  where QueryValue: QueryRepresentable, Joins == (), Key.QueryOutput: Hashable {
    try fetchAll(db, sectionBy: { $0[keyPath: sectionKeyPath] })
  }
}

private func sectionedResults<
  Value: QueryRepresentable,
  From: StructuredQueriesCore.Table,
  each J: StructuredQueriesCore.Table,
  Key: QueryRepresentable
>(
  _ db: Database,
  statement: Select<Value, From, (repeat each J)>,
  sectionBy: _Sectioning<Key>
) throws -> ResultsSectionCollection<Value.QueryOutput, Key.QueryOutput>
where Key.QueryOutput: Hashable {
  let ordered: Select<Value, From, (repeat each J)> =
    sectionedOrder(of: From.self, sectionBy) + statement
  let sectioned: Select<(Value, Key), From, (repeat each J)> =
    ordered + sectionedColumn(of: From.self, sectionBy)
  return try sectionedResults(Value.self, Key.self, db: db, query: sectioned.query)
}

private func sectionedResults<Value: QueryRepresentable, Key: QueryRepresentable>(
  _: Value.Type,
  _: Key.Type,
  db: Database,
  query: QueryFragment
) throws -> ResultsSectionCollection<Value.QueryOutput, Key.QueryOutput>
where Key.QueryOutput: Hashable {
  try ResultsSectionCollection(
    cursor: QuerySectionedCursor<Value, Key>(db: db, query: query, cached: true)
  )
}
