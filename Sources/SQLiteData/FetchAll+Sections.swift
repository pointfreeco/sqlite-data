public import GRDB
public import StructuredQueriesCore
import Sharing

#if canImport(SwiftUI)
  public import SwiftUI
#endif

extension FetchAll {
  /// The results of the query, grouped into sections.
  ///
  /// This collection is populated when the property is initialized with a `sectionBy:` key path:
  ///
  /// ```swift
  /// @FetchAll(Reminder.order(by: \.category), sectionBy: \.category)
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
    guard sectionedBy.withLock(\.self) != nil else {
      return ResultsSectionCollection(elements: sharedReader.wrappedValue, sectionName: "")
    }
    return sectionedReader.wrappedValue
  }

  fileprivate init<V: QueryRepresentable>(
    wrappedValue: [Element],
    statement: some StructuredQueriesCore.Statement<V>,
    sectionBy: SectionBy<Element>,
    database: (any DatabaseReader)?,
    scheduler: (any ValueObservationScheduler & Hashable)?
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    let request = FetchAllSectionedStatementValueRequest(statement: statement, sectionBy: sectionBy)
    let sectionedReader = SharedReader(
      wrappedValue: ResultsSectionCollection(elements: wrappedValue, sectionName: sectionBy.name),
      FetchKey(request: request, database: database, scheduler: scheduler)
    )
    self.sharedReader = sectionedReader[dynamicMember: \.elements]
    self.sectionedReader = sectionedReader
    self.sectionedBy.withLock { $0 = sectionBy }
    setFetchKeyID(for: request, database: database, scheduler: scheduler)
  }
}

extension FetchAll {
  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// Results are grouped into a section for each distinct value at the given key path. Sections
  /// are ordered by the position of their first element in the query's results, and elements
  /// within a section follow the query's order. Access the sections from the projected value's
  /// ``sections`` property.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<Element, Element, ()> = Element.all.selectStar().asSelect()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// Results are grouped into a section for each distinct value at the given key path. Sections
  /// are ordered by the position of their first element in the query's results, and elements
  /// within a section follow the query's order. To control the order of sections, order the query
  /// by the sectioned column:
  ///
  /// ```swift
  /// @FetchAll(Reminder.order(by: \.category), sectionBy: \.category)
  /// var reminders
  /// ```
  ///
  /// Access the sections from the projected value's ``sections`` property.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<Element, Element, ()> = Element.all.selectStar().asSelect()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }

  /// Initializes this property with a query associated with the wrapped value, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: nil
    )
  }
}

extension FetchAll {
  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<Element, Element, ()> = Element.all.selectStar().asSelect()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
      database: database,
      scheduler: scheduler
    )
  }

  /// Initializes this property with a query that fetches every row from a table, grouping results
  /// into sections.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: [Element] = [],
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement: Select<Element, Element, ()> = Element.all.selectStar().asSelect()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    guard let sectionKeyPath else {
      self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
      return
    }
    self.init(
      wrappedValue: wrappedValue,
      statement: statement,
      sectionBy: SectionBy(sectionKeyPath),
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
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: [Element] = [],
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
      self.init(
        wrappedValue: wrappedValue,
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement>(
      wrappedValue: [Element] = [],
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
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
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<V: QueryRepresentable>(
      wrappedValue: [Element] = [],
      _ statement: some StructuredQueriesCore.Statement<V>,
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: StructuredQueriesCore.Statement<Element>>(
      wrappedValue: [Element] = [],
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element: QueryRepresentable,
      Element == S.QueryValue.QueryOutput
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Initializes this property with a query that fetches every row from a table, grouping
    /// results into sections.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: [Element] = [],
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
      self.init(
        wrappedValue: wrappedValue,
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement>(
      wrappedValue: [Element] = [],
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
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
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<V: QueryRepresentable>(
      wrappedValue: [Element] = [],
      _ statement: some StructuredQueriesCore.Statement<V>,
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: sectionKeyPath,
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
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: StructuredQueriesCore.Statement<Element>>(
      wrappedValue: [Element] = [],
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element: QueryRepresentable,
      Element == S.QueryValue.QueryOutput
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }
  }
#endif

extension FetchAll {
  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    return try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: nil
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: nil
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// A `nil` value at the given key path is grouped into a section named by the empty string. The
  /// given key path replaces any sectioning previously applied to this property, and is used by
  /// all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    return try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: nil
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// A `nil` value at the given key path is grouped into a section named by the empty string. The
  /// given key path replaces any sectioning previously applied to this property, and is used by
  /// all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: nil
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    return try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: scheduler
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// The given key path replaces any sectioning previously applied to this property, and is used
  /// by all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to a string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: scheduler
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// A `nil` value at the given key path is grouped into a section named by the empty string. The
  /// given key path replaces any sectioning previously applied to this property, and is used by
  /// all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement: Select<S.From, S.From, ()> = statement.selectStar()
    return try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: scheduler
    )
  }

  /// Replaces the wrapped value with data from the given query, grouping results into sections.
  ///
  /// A `nil` value at the given key path is grouped into a section named by the empty string. The
  /// given key path replaces any sectioning previously applied to this property, and is used by
  /// all subsequent loads. Pass `nil` to remove sectioning from this property.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - sectionKeyPath: A key path to an optional string to group results by.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    sectionBy sectionKeyPath: KeyPath<Element, String?>?,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await loadSections(
      statement: statement,
      sectionBy: sectionKeyPath.map { SectionBy($0) },
      database: database,
      scheduler: scheduler
    )
  }

  func loadSections<V: QueryRepresentable>(
    statement: some StructuredQueriesCore.Statement<V>,
    sectionBy newSectionBy: SectionBy<Element>?,
    database: (any DatabaseReader)?,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    sectionedBy.withLock { $0 = newSectionBy }
    guard let newSectionBy else {
      sectionedReader.projectedValue = SharedReader(value: ResultsSectionCollection())
      try await sharedReader.load(
        FetchKey(
          request: FetchAllStatementValueRequest(statement: statement),
          database: database,
          scheduler: scheduler
        )
      )
      return FetchSubscription(sharedReader: sharedReader)
    }
    defer {
      sharedReader.projectedValue = sectionedReader[dynamicMember: \.elements].projectedValue
    }
    try await sectionedReader.load(
      FetchKey(
        request: FetchAllSectionedStatementValueRequest(
          statement: statement,
          sectionBy: newSectionBy
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
    /// The given key path replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<S: SelectStatement>(
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
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
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Replaces the wrapped value with data from the given query, grouping results into sections.
    ///
    /// The given key path replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to a string to group results by.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      sectionBy sectionKeyPath: KeyPath<Element, String>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation?
    ) async throws -> FetchSubscription
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      try await load(
        statement,
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Replaces the wrapped value with data from the given query, grouping results into sections.
    /// The given key path replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<S: SelectStatement>(
      _ statement: S,
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
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
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Replaces the wrapped value with data from the given query, grouping results into sections.
    /// The given key path replaces any sectioning previously applied to this property, and is
    /// used by all subsequent loads. Pass `nil` to remove sectioning from this property.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - sectionKeyPath: A key path to an optional string to group results by, or `nil` for
    ///     no grouping.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      sectionBy sectionKeyPath: KeyPath<Element, String?>?,
      database: (any DatabaseReader)? = nil,
      animation: Animation?
    ) async throws -> FetchSubscription
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      try await load(
        statement,
        sectionBy: sectionKeyPath,
        database: database,
        scheduler: .animation(animation)
      )
    }
  }
#endif

struct FetchAllSectionedStatementValueRequest<Value: QueryRepresentable>: FetchKeyRequest
where Value.QueryOutput: Sendable {
  let statement: SQLQueryExpression<Value>
  let sectionedBy: SectionBy<Value.QueryOutput>

  init(
    statement: some StructuredQueriesCore.Statement<Value>,
    sectionBy: SectionBy<Value.QueryOutput>
  ) {
    self.statement = SQLQueryExpression(statement)
    self.sectionedBy = sectionBy
  }

  func fetch(_ db: Database) throws -> ResultsSectionCollection<Value.QueryOutput, String> {
    try ResultsSectionCollection(
      cursor: statement.fetchCursor(db),
      sectionName: sectionedBy.name
    )
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.statement.query == rhs.statement.query && lhs.sectionedBy == rhs.sectionedBy
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(statement.query)
    hasher.combine(sectionedBy)
  }
}
