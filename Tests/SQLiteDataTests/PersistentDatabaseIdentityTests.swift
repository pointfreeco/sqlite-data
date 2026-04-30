import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import SQLiteData
import StructuredQueries
import Testing

@Suite("PersistentDatabaseIdentity")
struct PersistentDatabaseIdentityTests {

  @Test("Observers reattach to the new inner pool after a swap")
  @MainActor
  func observersReattachAfterSwap() async throws {
    let poolA = try makePool(suffix: "A")
    let wrapper = SwappableDatabase(inner: poolA)

    try await withDependencies {
      $0.defaultDatabase = wrapper
    } operation: {
      @FetchOne var unreadCount: Int = -1
      @FetchAll var items: [Item] = []

      try await $unreadCount.load(Item.unreadCountQuery())
      try await $items.load(Item.all)
      #expect(unreadCount == 0)
      #expect(items.isEmpty)

      try await wrapper.write { db in
        try Item.insert { Item(id: 1, isRead: false) }.execute(db)
      }
      try await Task.sleep(for: .milliseconds(200))
      #expect(unreadCount == 1)
      #expect(items.count == 1)

      let poolB = try makePool(suffix: "B")
      try? poolA.close()
      wrapper.swap(to: poolB)

      try await $unreadCount.load(Item.unreadCountQuery())
      try await $items.load(Item.all)
      try await Task.sleep(for: .milliseconds(200))
      #expect(unreadCount == 0)
      #expect(items.isEmpty)

      try await wrapper.write { db in
        try Item.insert { Item(id: 1, isRead: false) }.execute(db)
      }
      try await Task.sleep(for: .milliseconds(500))
      #expect(unreadCount == 1, "FetchOne must observe the post-swap write")
      #expect(items.count == 1, "FetchAll must observe the post-swap write")
    }
  }

  @Test("FetchKey cache is shared across wrappers that report the same identity")
  @MainActor
  func cacheKeyDerivesFromPersistentIdentity() async throws {
    let pool = try makePool(suffix: "shared")
    let wrapperA = SwappableDatabase(inner: pool)
    let wrapperB = SwappableDatabase(inner: pool)

    #expect(ObjectIdentifier(wrapperA) != ObjectIdentifier(wrapperB))
    #expect(wrapperA.persistentIdentity == wrapperB.persistentIdentity)

    try await withDependencies {
      $0.defaultDatabase = wrapperA
    } operation: {
      @FetchOne(Item.unreadCountQuery(), database: wrapperA) var fromA: Int = -1
      @FetchOne(Item.unreadCountQuery(), database: wrapperB) var fromB: Int = -1

      try await $fromA.load()
      try await $fromB.load()
      #expect(fromA == 0)
      #expect(fromB == 0)

      try await wrapperA.write { db in
        try Item.insert { Item(id: 1, isRead: false) }.execute(db)
      }
      try await Task.sleep(for: .milliseconds(200))
      #expect(fromA == 1)
      #expect(fromB == 1)
    }
  }
}

@Table private struct Item: Sendable {
  let id: Int
  var isRead: Bool
}

extension Item {
  fileprivate static func unreadCountQuery() -> some StructuredQueries.Statement<Int> {
    Item.where { $0.isRead.eq(false) }.select { $0.id.count() }
  }
}

private func makePool(suffix: String) throws -> DatabasePool {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("persistent-identity-\(suffix)-\(UUID()).sqlite")
  var config = Configuration()
  config.busyMode = .timeout(0.5)
  let pool = try DatabasePool(path: url.path, configuration: config)
  var migrator = DatabaseMigrator()
  migrator.registerMigration("v1") { db in
    try db.create(table: "items") { t in
      t.column("id", .integer).primaryKey()
      t.column("isRead", .boolean).notNull()
    }
  }
  try migrator.migrate(pool)
  return pool
}

// MARK: - Wrapper under test

/// Minimal transparent wrapper that mirrors the production pattern: stable
/// object identity across an inner-pool swap. Conforms to
/// `PersistentDatabaseIdentity` by forwarding to the current inner pool's
/// `ObjectIdentifier`, so a swap naturally invalidates the FetchKey cache.
private final class SwappableDatabase: DatabaseReader, DatabaseWriter, @unchecked Sendable {
  private let inner: LockIsolated<any DatabaseWriter>

  init(inner: any DatabaseWriter) {
    self.inner = LockIsolated(inner)
  }

  func swap(to newWriter: any DatabaseWriter) {
    inner.setValue(newWriter)
  }

  private var current: any DatabaseWriter { inner.value }

  // MARK: PersistentDatabaseIdentity

  // (extension below)

  // MARK: DatabaseReader forwarding

  var configuration: Configuration { current.configuration }
  var path: String { current.path }
  func close() throws { try current.close() }
  func interrupt() { current.interrupt() }

  func read<T>(_ value: (Database) throws -> T) throws -> T { try current.read(value) }
  func read<T: Sendable>(
    _ value: @escaping @Sendable (Database) throws -> T
  ) async throws -> T { try await current.read(value) }
  func asyncRead(_ value: @escaping @Sendable (Result<Database, any Error>) -> Void) {
    current.asyncRead(value)
  }
  func unsafeRead<T>(_ value: (Database) throws -> T) throws -> T { try current.unsafeRead(value) }
  func unsafeRead<T: Sendable>(
    _ value: @escaping @Sendable (Database) throws -> T
  ) async throws -> T { try await current.unsafeRead(value) }
  func asyncUnsafeRead(_ value: @escaping @Sendable (Result<Database, any Error>) -> Void) {
    current.asyncUnsafeRead(value)
  }
  func unsafeReentrantRead<T>(_ value: (Database) throws -> T) throws -> T {
    try current.unsafeReentrantRead(value)
  }
  func _add<Reducer: ValueReducer>(
    observation: ValueObservation<Reducer>,
    scheduling scheduler: some ValueObservationScheduler,
    onChange: @escaping @Sendable (Reducer.Value) -> Void
  ) -> AnyDatabaseCancellable {
    current._add(observation: observation, scheduling: scheduler, onChange: onChange)
  }

  // MARK: DatabaseWriter forwarding

  func writeWithoutTransaction<T>(_ updates: (Database) throws -> T) rethrows -> T {
    try current.writeWithoutTransaction(updates)
  }
  func writeWithoutTransaction<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T { try await current.writeWithoutTransaction(updates) }
  func barrierWriteWithoutTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
    try current.barrierWriteWithoutTransaction(updates)
  }
  func barrierWriteWithoutTransaction<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T { try await current.barrierWriteWithoutTransaction(updates) }
  func asyncBarrierWriteWithoutTransaction(
    _ updates: @escaping @Sendable (Result<Database, any Error>) -> Void
  ) { current.asyncBarrierWriteWithoutTransaction(updates) }
  func asyncWriteWithoutTransaction(_ updates: @escaping @Sendable (Database) -> Void) {
    current.asyncWriteWithoutTransaction(updates)
  }
  func unsafeReentrantWrite<T>(_ updates: (Database) throws -> T) rethrows -> T {
    try current.unsafeReentrantWrite(updates)
  }
  func spawnConcurrentRead(_ value: @escaping @Sendable (Result<Database, any Error>) -> Void) {
    current.spawnConcurrentRead(value)
  }
}

extension SwappableDatabase: PersistentDatabaseIdentity {
  fileprivate var persistentIdentity: AnyHashable {
    AnyHashable(ObjectIdentifier(inner.value as AnyObject))
  }
}
