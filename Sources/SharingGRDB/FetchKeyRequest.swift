import GRDB

/// A type that can request a value from a database.
///
/// This type can be used to describe a query to read data from SQLite:
///
/// ```swift
/// struct Players: FetchKeyRequest {
///   func fetch(_ db: Database) throws -> [Player] {
///     try Player
///       .where { !$0.isInjured }
///       .order(by: \.name)
///       .limit(10)
///       .fetchAll(db)
///   }
/// }
/// ```
///
/// And then can be used with `@SharedReader` and
/// ``Sharing/SharedReaderKey/fetch(_:database:animation:)-rgj4`` to popular state with the query
/// in a SwiftUI view, `@Observable` model, UIKit controller, and more:
///
/// ```swift
/// struct PlayersView: View {
///   @SharedReader(.fetch(Players())) var players
///
///   var body: some View {
///     ForEach(players) { player in
///       // ...
///     }
///   }
/// }
/// ```
public protocol FetchKeyRequest<Value>: Hashable, Sendable {
  associatedtype Value
  func fetch(_ db: Database) throws -> Value
}
