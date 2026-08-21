import GRDBSQLite
public import StructuredQueriesSQLiteCore

#if EXCLUDE_EXPORTS
  // NB: This 'public import' breaks the '@_exported import'.
  public import class GRDB.Database
#endif

extension Database {
  /// Adds a user-defined `@DatabaseCollation` to a connection.
  ///
  /// - Parameter collation: A database collation to add.
  public func add(collation: some DatabaseCollation) {
    sqlite3_create_collation_v2(
      sqliteConnection,
      collation.name,
      SQLITE_UTF8,
      Unmanaged.passRetained(DatabaseCollationDefinition(collation)).toOpaque(),
      { context, lhsCount, lhs, rhsCount, rhs in
        switch Unmanaged<DatabaseCollationDefinition>
          .fromOpaque(context!)
          .takeUnretainedValue()
          .collation
          .compare(
            UnsafeRawBufferPointer(start: lhs, count: Int(lhsCount)),
            UnsafeRawBufferPointer(start: rhs, count: Int(rhsCount))
          )
        {
        case .ascending: return -1
        case .same: return 0
        case .descending: return 1
        }
      },
      { context in
        guard let context else { return }
        Unmanaged<DatabaseCollationDefinition>.fromOpaque(context).release()
      }
    )
  }

  /// Deletes a user-defined `@DatabaseCollation` from a connection.
  ///
  /// - Parameter collation: A database collation to delete.
  public func remove(collation: some DatabaseCollation) {
    sqlite3_create_collation_v2(
      sqliteConnection,
      collation.name,
      SQLITE_UTF8,
      nil,
      nil,
      nil
    )
  }
}

extension Collation where Self == CanonicalCollation {
  /// Orders text by Unicode Canonical Equivalence.
  ///
  /// This collating sequence orders text the same way as Swift's String type.
  ///
  /// > Tip: This collating sequence is automatically installed by
  /// > ``defaultDatabase(path:configuration:)``. To manually install it, use
  /// > ``GRDB/Database/add(collation:)``:
  /// >
  /// > ```swift
  /// > configuration.prepareDatabase { db in
  /// >   db.add(collation: .canonical)
  /// > }
  /// > ```
  public static var canonical: Self { Self() }
}

/// A collating sequence that orders text by Unicode Canonical Equivalence.
public nonisolated struct CanonicalCollation: DatabaseCollation, Sendable {
  public var name: String { "canonical" }
  public init() {}
  public func compare(
    _ lhs: UnsafeRawBufferPointer, _ rhs: UnsafeRawBufferPointer
  ) -> CollationOrder {
    #if compiler(>=6.2)
      if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
        do {
          let lhsSpan = try UTF8Span(validating: lhs.assumingMemoryBound(to: UInt8.self).span)
          let rhsSpan = try UTF8Span(validating: rhs.assumingMemoryBound(to: UInt8.self).span)
          if lhsSpan.isCanonicallyLessThan(rhsSpan) { return .ascending }
          if rhsSpan.isCanonicallyLessThan(lhsSpan) { return .descending }
          return .same
        } catch {
          return lhs.elementsEqual(rhs)
            ? .same
            : lhs.lexicographicallyPrecedes(rhs) ? .ascending : .descending
        }
      }
    #endif
    return CollationOrder(
      String(decoding: lhs, as: UTF8.self), String(decoding: rhs, as: UTF8.self)
    )
  }
}

private final class DatabaseCollationDefinition {
  let collation: any DatabaseCollation
  init(_ collation: some DatabaseCollation) {
    self.collation = collation
  }
}
