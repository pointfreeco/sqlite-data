public import GRDB
public import StructuredQueriesCore
import Sharing

#if canImport(SwiftUI)
  public import SwiftUI
#endif

extension FetchAll {
  /// The results of the query, grouped into sections.
  ///
  /// This collection is populated when the property is initialized with a `sectionBy:` expression:
  ///
  /// ```swift
  /// @FetchAll(Reminder.order(by: \.title), sectionBy: \.category)
  /// var reminders
  ///
  /// var body: some View {
  ///   List {
  ///     ForEach($reminders.sections) { section in
  ///       Section(section.name) {
  ///         ForEach(section) { reminder in
  ///           Text(reminder.title)
  ///         }
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// See ``ResultsSectionCollection`` for more information.
  public var sections: ResultsSectionCollection<Element, String> {
    guard sectionedBy.value != nil else {
      return ResultsSectionCollection(elements: sharedReader.wrappedValue, sectionName: "")
    }
    return sectionedReader.wrappedValue
  }

  fileprivate init<From: StructuredQueriesCore.Table>(
    wrappedValue: [Element],
    statement: Select<(), From, ()>,
    sectionBy: _SectionBy,
    database: (any DatabaseReader)?,
    scheduler: (any ValueObservationScheduler & Hashable)?
  )
  where
    Element == From.QueryOutput,
    From.QueryOutput: Sendable
  {
    let sectionedReader = SharedReader(
      wrappedValue: ResultsSectionCollection(elements: wrappedValue, sectionName: ""),
      FetchKey(
        request: FetchAllSectionedStatementValueRequest(statement: statement, sectionBy: sectionBy),
        database: database,
        scheduler: scheduler
      )
    )
    self.sectionedReader = sectionedReader
    self.sharedReader = sectionedReader.elements
    self.sectionedBy.setValue(sectionBy)
  }
}

extension FetchAll {
  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// Results are ordered by the given expression and grouped into a section for each of its
  /// distinct values. The expression is evaluated by the database, and its value, formatted as
  /// text, names each section. Access the sections from the projected value's ``sections``
  /// property.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: [Element] = [],
    @_SectionBuilder sectionBy sectioning: (Element.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<(), Element, ()> = Element.all.asSelect()
    guard let sectionBy = sectioning(Element.columns) else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: sectionBy,
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// Results are ordered by the given expression and grouped into a section for each of its
  /// distinct values:
  ///
  /// ```swift
  /// @FetchAll(Reminder.order(by: \.title), sectionBy: \.category)
  /// var reminders
  /// ```
  ///
  /// The expression is prepended to the query's `ORDER BY` clause so that sections are ordered by
  /// the expression, and elements within a section follow the query's order. Sections are ordered
  /// ascending by default, and the expression can be ordered explicitly to control the direction
  /// and `NULL` ordering of sections:
  ///
  /// ```swift
  /// @FetchAll(Reminder.order(by: \.title), sectionBy: { $0.category.desc() })
  /// var reminders
  /// ```
  ///
  /// The expression is evaluated by the database, and its value, formatted as text, names each
  /// section. Access the sections from the projected value's ``sections`` property.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<(), S.From, ()> = statement.asSelect()
    guard let sectionBy = sectioning(S.From.columns) else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: sectionBy,
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: [Element] = [],
    @_SectionBuilder sectionBy sectioning: (Element.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<(), Element, ()> = Element.all.asSelect()
    guard let sectionBy = sectioning(Element.columns) else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: sectionBy,
      database: database,
      scheduler: scheduler
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<(), S.From, ()> = statement.asSelect()
    guard let sectionBy = sectioning(S.From.columns) else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: sectionBy,
      database: database,
      scheduler: scheduler
    )
  }
}

#if canImport(SwiftUI)
  extension FetchAll {
    /// Initializes this property with a query that fetches every row from a table, grouping
    /// results into sections.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - sectioning: A closure that returns a string expression, or an ordering of one, to
    ///     group results by, or `nil` for no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: [Element] = [],
      @_SectionBuilder sectionBy sectioning: (Element.TableColumns) -> _SectionBy?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
      self.init(
        wrappedValue: wrappedValue,
        sectionBy: sectioning,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Initializes this property with a query associated with the wrapped value, grouping results
    /// into sections.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - sectioning: A closure that returns a string expression, or an ordering of one, to
    ///     group results by, or `nil` for no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement>(
      wrappedValue: [Element] = [],
      _ statement: S,
      @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: sectioning,
        database: database,
        scheduler: .animation(animation)
      )
    }
  }
#endif

extension FetchAll {
  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given expression replaces any sectioning previously applied to this property, and is
  /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<(), S.From, ()> = statement.asSelect()
    return try await loadSections(
      statement: statement,
      sectionBy: sectioning(S.From.columns),
      database: database,
      scheduler: nil
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given expression replaces any sectioning previously applied to this property, and is
  /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectioning: A closure that returns a string expression, or an ordering of one, to group
  ///     results by, or `nil` for no grouping.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<(), S.From, ()> = statement.asSelect()
    return try await loadSections(
      statement: statement,
      sectionBy: sectioning(S.From.columns),
      database: database,
      scheduler: scheduler
    )
  }

  func loadSections<From: StructuredQueriesCore.Table>(
    statement: Select<(), From, ()>,
    sectionBy sectioning: _SectionBy?,
    database: (any DatabaseReader)?,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) async throws -> FetchSubscription
  where
    Element == From.QueryOutput,
    From.QueryOutput: Sendable
  {
    guard let sectioning else {
      removeSections()
      let statement: Select<From, From, ()> = statement.selectStar()
      try await sharedReader.load(
        FetchKey(
          request: FetchAllStatementValueRequest(statement: statement),
          database: database,
          scheduler: scheduler
        )
      )
      return FetchSubscription(sharedReader: sharedReader)
    }
    sectionedBy.setValue(sectioning)
    defer {
      sharedReader.projectedValue = sectionedReader.elements.projectedValue
    }
    try await sectionedReader.load(
      FetchKey(
        request: FetchAllSectionedStatementValueRequest(
          statement: statement,
          sectionBy: sectioning
        ),
        database: database,
        scheduler: scheduler
      )
    )
    return FetchSubscription(sharedReader: sharedReader, sectionedReader: sectionedReader)
  }
}

#if canImport(SwiftUI)
  extension FetchAll {
    /// Replaces the wrapped value with data from the given query, grouping results into sections.
    ///
    /// The given expression replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectioning: A closure that returns a string expression, or an ordering of one, to
    ///     group results by, or `nil` for no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<S: SelectStatement>(
      _ statement: S,
      @_SectionBuilder sectionBy sectioning: (S.From.TableColumns) -> _SectionBy?,
      database: (any DatabaseReader)? = nil,
      animation: Animation?
    ) async throws -> FetchSubscription
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      try await load(
        statement,
        sectionBy: sectioning,
        database: database,
        scheduler: .animation(animation)
      )
    }
  }
#endif

extension FetchAll {
  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<
      Element.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    self.init(
      wrappedValue: wrappedValue,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<
      S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    self.init(
      wrappedValue: wrappedValue,
      statement,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database
    )
  }

  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<
      Element.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    self.init(
      wrappedValue: wrappedValue,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database,
      scheduler: scheduler
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<
      S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    self.init(
      wrappedValue: wrappedValue,
      statement,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database,
      scheduler: scheduler
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<
      S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    try await load(
      statement,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string column to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<
      S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
    >,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    try await load(
      statement,
      sectionBy: { $0[keyPath: sectionKeyPath] },
      database: database,
      scheduler: scheduler
    )
  }
}

#if canImport(SwiftUI)
  extension FetchAll {
    /// Initializes this property with a query that fetches every row from a table, grouping
    /// results into sections.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - sectionKeyPath: A key path to a string column to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: [Element] = [],
      sectionBy sectionKeyPath: KeyPath<
        Element.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
      >,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
      self.init(
        wrappedValue: wrappedValue,
        sectionBy: { $0[keyPath: sectionKeyPath] },
        database: database,
        animation: animation
      )
    }

    /// Initializes this property with a query associated with the wrapped value, grouping results
    /// into sections.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to a string column to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement>(
      wrappedValue: [Element] = [],
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<
        S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
      >,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: { $0[keyPath: sectionKeyPath] },
        database: database,
        animation: animation
      )
    }

    /// Replaces the wrapped value with data from the given query, grouping results into sections.
    ///
    /// The given key path replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to a string column to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<S: SelectStatement>(
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<
        S.From.TableColumns, some QueryExpression<some _OptionalPromotable<String?>>
      >,
      database: (any DatabaseReader)? = nil,
      animation: Animation?
    ) async throws -> FetchSubscription
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      try await load(
        statement,
        sectionBy: { $0[keyPath: sectionKeyPath] },
        database: database,
        animation: animation
      )
    }
  }
#endif

public struct _SectionBy: Hashable, Sendable {
  let select: QueryFragment
  let order: QueryFragment

  package init(_ expression: some QueryExpression<some _OptionalPromotable<String?>>) {
    self.select = expression.queryFragment
    self.order = expression.queryFragment
  }

  package init(_ orderingTerm: _OrderingTerm<some _OptionalPromotable<String?>>) {
    self.select = orderingTerm.base
    self.order = orderingTerm.queryFragment
  }
}

@resultBuilder
public enum _SectionBuilder {
  public static func buildExpression(
    _ expression: some QueryExpression<some _OptionalPromotable<String?>>
  ) -> _SectionBy {
    _SectionBy(expression)
  }

  public static func buildExpression(
    _ orderingTerm: _OrderingTerm<some _OptionalPromotable<String?>>
  ) -> _SectionBy {
    _SectionBy(orderingTerm)
  }

  public static func buildBlock(_ component: _SectionBy) -> _SectionBy {
    component
  }

  public static func buildBlock(_ component: _SectionBy?) -> _SectionBy? {
    component
  }

  public static func buildOptional(_ component: _SectionBy?) -> _SectionBy? {
    component
  }

  public static func buildEither(first component: _SectionBy) -> _SectionBy {
    component
  }

  public static func buildEither(second component: _SectionBy) -> _SectionBy {
    component
  }
}

struct FetchAllSectionedStatementValueRequest<From: StructuredQueriesCore.Table>: FetchKeyRequest
where From.QueryOutput: Sendable {
  let statement: SQLQueryExpression<(From, String?)>

  init(
    statement: Select<(), From, ()>,
    sectionBy: _SectionBy
  ) {
    let prefix: Select<(), From, ()> = From.unscoped.asSelect()
      .order { _ in SQLQueryExpression(sectionBy.order) }
    let ordered: Select<(), From, ()> = prefix + statement
    let sectioned: Select<(From, String?), From, ()> = ordered.select {
      ($0, SQLQueryExpression(sectionBy.select, as: String?.self))
    }
    self.statement = SQLQueryExpression(sectioned)
  }

  func fetch(_ db: Database) throws -> ResultsSectionCollection<From.QueryOutput, String> {
    try ResultsSectionCollection(
      cursor: QuerySectionedValueCursor<From>(db: db, query: statement.queryFragment)
    )
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.statement.query == rhs.statement.query
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(statement.query)
  }
}
