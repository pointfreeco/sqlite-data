import Foundation
import GRDB

/// A hook that lets transparent `DatabaseReader` wrappers participate in
/// `FetchKey`'s persistent-reference cache.
///
/// `FetchKey` keys cached references in part by an identifier derived from the
/// `DatabaseReader`. By default that identifier is `ObjectIdentifier(database)`,
/// which is stable for plain `DatabasePool` / `DatabaseQueue`. A wrapper that
/// swaps its inner pool while keeping its own object identity stable (e.g. an
/// account-switch wrapper) breaks this assumption: the cached reference's
/// `ValueObservation` stays bound to the previous inner pool, and writes
/// against the new pool never reach `@FetchOne` / `@FetchAll` observers.
///
/// Wrappers that swap their inner reader can conform to this protocol and
/// forward `persistentIdentity` to whatever uniquely identifies the *current*
/// inner connection. After a swap the value must differ from the value before
/// the swap, so the cache invalidates and the next `.load` rebuilds the
/// subscription against the new connection.
///
/// ```swift
/// extension AccountDatabase: PersistentDatabaseIdentity {
///   var persistentIdentity: AnyHashable {
///     AnyHashable(ObjectIdentifier(currentInnerPool))
///   }
/// }
/// ```
public protocol PersistentDatabaseIdentity {
  /// A stable, hashable identity for the current underlying connection.
  ///
  /// Two reads against the same conceptual connection return equal values; a
  /// swap of the underlying connection produces a different value.
  var persistentIdentity: AnyHashable { get }
}
