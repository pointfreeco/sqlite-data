/// A type that can request a value from a database.
///
/// This type can be used to describe a transaction to read data from SQLite:
///
/// ```swift
/// struct PlayersRequest: FetchKeyRequest {
///   struct Value {
///     let injuredPlayerCount: Int
///     let players: [Player]
///   }
///
///   func fetch(_ db: Database) throws -> Value {
///     try Value(
///       injuredPlayerCount: Player
///         .where(\.isInjured)
///         .fetchCount(db),
///       players: Player
///         .where { !$0.isInjured }
///         .order(by: \.name)
///         .limit(10)
///         .fetchAll(db)
///     )
///   }
/// }
/// ```
///
/// And then can be used with the ``Fetch`` property wrapper to populate state in a SwiftUI view,
/// `@Observable` model, UIKit view controller, and more:
///
/// ```swift
/// struct PlayersView: View {
///   @Fetch(PlayersRequest()) var response
///
///   var body: some View {
///     ForEach(response.players) { player in
///       // ...
///     }
///     Button("View injured players (\(response.injuredPlayerCount))") {
///       // ...
///     }
///   }
/// }
/// ```
public protocol FetchKeyRequest<Value>: Hashable, Sendable {
  /// The type associated with the request.
  associatedtype Value

  /// Fetches a value from a database.
  func fetch(_ db: Database) throws -> Value
}
