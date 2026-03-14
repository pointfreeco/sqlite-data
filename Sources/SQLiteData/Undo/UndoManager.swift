import ConcurrencyExtras
import Dependencies
import Foundation
import GRDB
import IssueReporting
import Perception
#if canImport(Observation)
  import Observation
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif
import StructuredQueriesCore

/// Tracks changes made to a SQLite database and lets you undo and redo them.
///
/// Prefer ``SQLiteUndoManager`` in your code when you also work with `Foundation.UndoManager`.
///
/// Create an `UndoManager` after the database is open, supplying the table names whose changes
/// you want to track.  The manager installs lightweight SQLite triggers that record inverse SQL
/// statements into a temporary log table.
///
/// ```swift
/// let undoManager = try UndoManager(
///   for: database,
///   tables: Reminder.self, ReminderTag.self
/// )
///
/// // Record a named group of changes
/// try await undoManager.withGroup("Add reminder") { db in
///   try Reminder.insert { Reminder.Draft(title: "Buy milk") }.execute(db)
/// }
///
/// // Undo the most-recent group
/// try await undoManager.undo()
/// ```
///
/// ## CloudKit sync compatibility
///
/// Changes written by a `SyncEngine` can be recorded as undo groups, including synced-origin
/// metadata.
public final class UndoManager: Perceptible, @unchecked Sendable {
  private final class WeakUndoManager: @unchecked Sendable {
    weak var value: UndoManager?
    init(_ value: UndoManager) {
      self.value = value
    }
  }

  private static let _managersByID = LockIsolated([ObjectIdentifier: WeakUndoManager]())
  // MARK: - Internal state

  private struct State {
    var undoEntries: [UndoEntry] = []
    var redoEntries: [UndoEntry] = []
    var activeBarrier: (id: UUID, barrier: OpenBarrier)?
    /// The next `seq` value that will begin a new undo group.
    var firstLog: Int = 1
    /// The first log sequence captured by the outermost freeze.
    var freezePoint: Int = -1
    /// Nesting count for `freeze()`/`unfreeze()`.
    var freezeDepth: Int = 0
  }

  private struct OpenBarrier: Sendable {
    var group: UndoGroup
    var firstLog: Int
  }

  public enum BarrierError: Error {
    case alreadyOpen
    case notFound
  }

  /// Summary information for a recorded sync undo group.
  public struct SyncUndoSummary: Sendable {
    /// Table names touched by the recorded sync group.
    public let affectedTables: Set<String>
    /// Number of inverse log entries captured for the sync group.
    public let changeCount: Int

    public init(affectedTables: Set<String>, changeCount: Int) {
      self.affectedTables = affectedTables
      self.changeCount = changeCount
    }
  }

  /// Behavior for history around sync changes when sync undo registration is disabled.
  public enum SyncBoundaryBehavior: Sendable {
    /// Keep existing local undo history, allowing undo operations to cross past sync changes.
    case allowCrossing
    /// Prevent undo from crossing sync changes by clearing undo/redo history at each sync write.
    case stopAtBoundary
  }

  /// How a sync write entered the system.
  package enum SyncChangeKind: Sendable {
    /// Echo-back from successfully sending local changes to CloudKit.
    case sent
    /// Remote changes fetched from CloudKit.
    case fetched
  }

  /// Controls redo stack behavior when remote sync changes arrive.
  public enum SyncRedoPolicy: Sendable {
    /// Clear the redo stack when remote sync changes are recorded.
    case clear
    /// Preserve the redo stack. Use the delegate to confirm redo after sync changes.
    case preserve
  }

  /// Policy controlling how sync-applied writes interact with undo history.
  public enum SyncUndoPolicy: Sendable {
    /// Record sync changes as undo groups.
    ///
    /// The `actionName` closure customizes each sync undo group's description.
    case enabled(
      actionName: @Sendable (_ summary: SyncUndoSummary) -> String = { _ in "Sync iCloud changes" }
    )
    /// Do not register sync changes as undo groups.
    ///
    /// Use `boundary` to control whether existing local history can be undone past sync writes.
    case disabled(boundary: SyncBoundaryBehavior = .stopAtBoundary)
  }

  private let _state = LockIsolated(State())
  private let database: any DatabaseWriter
  private let databaseID: ObjectIdentifier
  private let trackedTableNames: Set<String>
  private let syncUndoPolicy: SyncUndoPolicy
  private let syncRedoPolicy: SyncRedoPolicy
  private let delegate: (any UndoManagerDelegate)?
  private let eventsContinuation: AsyncStream<UndoEvent>.Continuation
  public let events: AsyncStream<UndoEvent>
  #if canImport(ObjectiveC)
    private weak var foundationUndoManager: Foundation.UndoManager?
  #endif

  // MARK: - Observable conformance (Perception)

  private let _$perceptionRegistrar = PerceptionRegistrar()

  nonisolated public func access<Member>(
    keyPath: KeyPath<UndoManager, Member>
  ) {
    _$perceptionRegistrar.access(self, keyPath: keyPath)
  }

  nonisolated public func withMutation<Member, T>(
    keyPath: KeyPath<UndoManager, Member>,
    _ mutation: () throws -> T
  ) rethrows -> T {
    try _$perceptionRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
  }

  // MARK: - Observable state

  /// The groups that can be undone, most-recent-first.
  public var undoStack: [UndoGroup] {
    _$perceptionRegistrar.access(self, keyPath: \.undoStack)
    return _state.value.undoEntries.reversed().map(\.group)
  }

  /// The groups that can be redone, most-recent-first.
  public var redoStack: [UndoGroup] {
    _$perceptionRegistrar.access(self, keyPath: \.redoStack)
    return _state.value.redoEntries.reversed().map(\.group)
  }

  /// Whether there is at least one group that can be undone.
  public var canUndo: Bool { !undoStack.isEmpty }

  /// Whether there is at least one group that can be redone.
  public var canRedo: Bool { !redoStack.isEmpty }

  /// Returns `true` if any sync-origin groups exist on the undo stack with a date after the
  /// given group's date.
  public func hasSyncChangesSince(_ group: UndoGroup) -> Bool {
    undoStack.contains { $0.origin == .sync && $0.date > group.date }
  }

  // MARK: - Init

  /// Creates an undo manager and installs undo triggers on the database.
  ///
  /// The triggers and the temporary log table are created immediately on the writer connection.
  ///
  /// - Parameters:
  ///   - database: The database to observe.
  ///   - tables: The names of the tables whose changes should be undoable.
  ///   - syncUndoPolicy: Controls whether sync changes are recorded as undo groups and whether
  ///     undo history can cross sync boundaries when not recorded.
  ///   - syncRedoPolicy: Controls whether the redo stack is cleared when remote sync changes
  ///     arrive. Defaults to `.clear` to match existing behavior.
  ///   - delegate: An optional delegate that can intercept and confirm undo/redo operations.
  public init<
    each T: PrimaryKeyedTable & _SendableMetatype
  >(
    for database: any DatabaseWriter,
    tables: repeat (each T).Type,
    syncUndoPolicy: SyncUndoPolicy = .enabled(),
    syncRedoPolicy: SyncRedoPolicy = .preserve,
    delegate: (any UndoManagerDelegate)? = nil
  ) throws {
    var trackedTableNames = Set<String>()
    for table in repeat each tables {
      trackedTableNames.insert(table.tableName)
    }
    (self.events, self.eventsContinuation) = AsyncStream.makeStream()
    self.database = database
    self.databaseID = ObjectIdentifier(database as AnyObject)
    self.syncUndoPolicy = syncUndoPolicy
    self.syncRedoPolicy = syncRedoPolicy
    self.delegate = delegate
    self.trackedTableNames = trackedTableNames

    // One-time setup on the writer connection: register the custom function,
    // create the temp log table, and install triggers for each observed table.
    try database.write { db in
      db.add(function: $_shouldRecord)
      db.add(function: $_isReplaying)

      try #sql("\(raw: undoLogTableSQL)").execute(db)

      for table in repeat each tables {
        try table.installUndoTriggers(in: db)
      }
    }

    Self._managersByID.withValue {
      $0[self.databaseID] = WeakUndoManager(self)
    }
  }

  deinit {
    Self._managersByID.withValue {
      if $0[self.databaseID]?.value === self {
        $0.removeValue(forKey: self.databaseID)
      }
    }
  }

  package static func manager(for database: any DatabaseWriter) -> UndoManager? {
    _managersByID.withValue {
      $0 = $0.filter { $0.value.value != nil }
      return $0[ObjectIdentifier(database as AnyObject)]?.value
    }
  }

  package static func manager(
    for database: any DatabaseWriter,
    defaultUndoManager: UndoManager?
  ) -> UndoManager? {
    (defaultUndoManager?.manages(database: database) == true ? defaultUndoManager : nil)
      ?? manager(for: database)
  }

  package func manages(database: any DatabaseWriter) -> Bool {
    databaseID == ObjectIdentifier(database as AnyObject)
  }

  #if canImport(ObjectiveC)
    /// Binds this manager to Foundation's undo manager for seamless system undo/redo integration.
    ///
    /// When bound, SQLiteData undo/redo operations are registered with the Foundation manager so
    /// keyboard shortcuts and responder-chain undo work with the same stack.
    public func bind(to foundationUndoManager: Foundation.UndoManager?) {
      self.foundationUndoManager = foundationUndoManager
    }
  #endif

  // MARK: - Static helpers

  /// A SQL expression that reports whether undo/redo replay is currently executing.
  ///
  /// Use this in application trigger `WHEN` clauses to suppress side-effect writes during replay.
  public static func isReplaying() -> some QueryExpression<Bool> {
    $_isReplaying()
  }

  // MARK: - Group recording

  /// Begins recording a barrier that can later be ended or cancelled.
  ///
  /// This overload accepts a localized resource so group names can participate in localization.
  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  @discardableResult
  public func beginBarrier(
    _ description: LocalizedStringResource,
    origin: UndoGroup.Origin = .local
  ) throws -> UUID {
    try beginBarrier(
      String(localized: description),
      origin: origin
    )
  }

  #if canImport(SwiftUI)
    /// Begins recording a barrier that can later be ended or cancelled.
    ///
    /// This overload accepts a localized key and resolves it using the app's main bundle.
    @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
    @_disfavoredOverload
    @discardableResult
    public func beginBarrier(
      _ description: LocalizedStringKey,
      origin: UndoGroup.Origin = .local
    ) throws -> UUID {
      try beginBarrier(
        description.undoGroupKeyString,
        origin: origin
      )
    }
  #endif

  /// Begins recording a barrier that can later be ended or cancelled.
  ///
  /// Use this API when an undoable action spans multiple writes or async boundaries.
  @_disfavoredOverload
  @discardableResult
  public func beginBarrier(
    _ description: String,
    origin: UndoGroup.Origin = .local
  ) throws -> UUID {
    @Dependency(\.date.now) var now
    let group = UndoGroup(
      description: description,
      origin: origin,
      date: now
    )
    let barrierID = UUID()
    try _state.withValue { state in
      guard state.activeBarrier == nil else { throw BarrierError.alreadyOpen }
      state.activeBarrier = (
        id: barrierID,
        barrier: OpenBarrier(group: group, firstLog: state.firstLog)
      )
    }
    return barrierID
  }

  /// Ends a previously opened barrier and pushes it to undo history if changes were recorded.
  @discardableResult
  public func endBarrier(_ barrierID: UUID) throws -> UndoGroup? {
    let barrier = try _state.withValue { state -> OpenBarrier in
      guard let activeBarrier = state.activeBarrier, activeBarrier.id == barrierID else {
        throw BarrierError.notFound
      }
      state.activeBarrier = nil
      return activeBarrier.barrier
    }
    let summary = try database.write { db -> (maxSeq: Int, modifiedTables: Set<String>)? in
      guard var maxSeq = try UndoLog.order(by: { $0.seq.desc() }).fetchOne(db)?.seq,
        maxSeq >= barrier.firstLog
      else {
        return nil
      }
      try undoReconcileEntries(in: db, from: barrier.firstLog, to: maxSeq)
      maxSeq = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq ?? 0
      guard maxSeq >= barrier.firstLog else { return nil }
      return (maxSeq, try undoModifiedTableNames(in: db, from: barrier.firstLog, to: maxSeq))
    }
    guard let summary else { return nil }
    return finalizeBarrier(
      barrier,
      maxSeq: summary.maxSeq,
      modifiedTables: summary.modifiedTables
    )
  }

  /// Async variant of ``endBarrier(_:)``.
  @discardableResult
  public func endBarrier(_ barrierID: UUID) async throws -> UndoGroup? {
    let barrier = try _state.withValue { state -> OpenBarrier in
      guard let activeBarrier = state.activeBarrier, activeBarrier.id == barrierID else {
        throw BarrierError.notFound
      }
      state.activeBarrier = nil
      return activeBarrier.barrier
    }
    let summary = try await database.write { db -> (maxSeq: Int, modifiedTables: Set<String>)? in
      guard var maxSeq = try UndoLog.order(by: { $0.seq.desc() }).fetchOne(db)?.seq,
        maxSeq >= barrier.firstLog
      else {
        return nil
      }
      try undoReconcileEntries(in: db, from: barrier.firstLog, to: maxSeq)
      maxSeq = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq ?? 0
      guard maxSeq >= barrier.firstLog else { return nil }
      return (maxSeq, try undoModifiedTableNames(in: db, from: barrier.firstLog, to: maxSeq))
    }
    guard let summary else { return nil }
    return finalizeBarrier(
      barrier,
      maxSeq: summary.maxSeq,
      modifiedTables: summary.modifiedTables
    )
  }

  /// Cancels a previously opened barrier and discards any undo log entries captured for it.
  public func cancelBarrier(_ barrierID: UUID) throws {
    let barrier = try _state.withValue { state -> OpenBarrier in
      guard let activeBarrier = state.activeBarrier, activeBarrier.id == barrierID else {
        throw BarrierError.notFound
      }
      state.activeBarrier = nil
      return activeBarrier.barrier
    }
    try database.write { db in
      try UndoLog
        .where { $0.seq >= barrier.firstLog }
        .delete()
        .execute(db)
    }
    _state.withValue { state in
      state.firstLog = barrier.firstLog
    }
  }

  /// Async variant of ``cancelBarrier(_:)``.
  public func cancelBarrier(_ barrierID: UUID) async throws {
    let barrier = try _state.withValue { state -> OpenBarrier in
      guard let activeBarrier = state.activeBarrier, activeBarrier.id == barrierID else {
        throw BarrierError.notFound
      }
      state.activeBarrier = nil
      return activeBarrier.barrier
    }
    try await database.write { db in
      try UndoLog
        .where { $0.seq >= barrier.firstLog }
        .delete()
        .execute(db)
    }
    _state.withValue { state in
      state.firstLog = barrier.firstLog
    }
  }

  /// Performs `body` inside a database write transaction and records all changes as a named
  /// undo group.
  ///
  /// If `body` makes no changes (or triggers are suppressed because recording is frozen), no
  /// undo entry is added.
  ///
  /// Calling this method clears the redo stack.
  ///
  /// - Parameters:
  ///   - description: A human-readable label for the change, e.g. `"Delete reminder"`.
  ///   - body: A closure that performs database writes.  Receives a `Database` connection.
  /// - Returns: The value returned by `body`.
  #if canImport(SwiftUI)
    @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
    @_disfavoredOverload
    @discardableResult
    public func withGroup<T: Sendable>(
      _ description: LocalizedStringKey,
      origin: UndoGroup.Origin = .local,
      _ body: @Sendable (Database) throws -> T
    ) async throws -> T {
      try await withGroup(
        description.undoGroupKeyString,
        origin: origin,
        body
      )
    }
  #endif

  /// Performs `body` inside a database write transaction and records all changes as a named
  /// undo group.
  ///
  /// If `body` makes no changes (or triggers are suppressed because recording is frozen), no
  /// undo entry is added.
  ///
  /// Calling this method clears the redo stack.
  ///
  /// - Parameters:
  ///   - description: A human-readable label for the change, e.g. `"Delete reminder"`.
  ///   - body: A closure that performs database writes.  Receives a `Database` connection.
  /// - Returns: The value returned by `body`.
  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  @discardableResult
  public func withGroup<T: Sendable>(
    _ description: LocalizedStringResource,
    origin: UndoGroup.Origin = .local,
    _ body: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withGroup(
      String(localized: description),
      origin: origin,
      body
    )
  }

  /// Performs `body` inside a database write transaction and records all changes as a named
  /// undo group.
  ///
  /// If `body` makes no changes (or triggers are suppressed because recording is frozen), no
  /// undo entry is added.
  ///
  /// Calling this method clears the redo stack.
  ///
  /// - Parameters:
  ///   - description: A human-readable label for the change, e.g. `"Delete reminder"`.
  ///   - body: A closure that performs database writes.  Receives a `Database` connection.
  /// - Returns: The value returned by `body`.
  @_disfavoredOverload
  @discardableResult
  public func withGroup<T: Sendable>(
    _ description: String,
    origin: UndoGroup.Origin = .local,
    _ body: @Sendable (Database) throws -> T
  ) async throws -> T {
    let barrierID = try beginBarrier(
      description,
      origin: origin
    )
    do {
      let result = try await database.write { db in
        try body(db)
      }
      _ = try await endBarrier(barrierID)
      return result
    } catch {
      try await cancelBarrier(barrierID)
      throw error
    }
  }

  /// Synchronous variant of ``withGroup(_:origin:_:)``.
  #if canImport(SwiftUI)
    @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
    @_disfavoredOverload
    @discardableResult
    public func withGroup<T>(
      _ description: LocalizedStringKey,
      origin: UndoGroup.Origin = .local,
      _ body: (Database) throws -> T
    ) throws -> T {
      try withGroup(
        description.undoGroupKeyString,
        origin: origin,
        body
      )
    }
  #endif

  /// Synchronous variant of ``withGroup(_:origin:_:)``.
  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  @discardableResult
  public func withGroup<T>(
    _ description: LocalizedStringResource,
    origin: UndoGroup.Origin = .local,
    _ body: (Database) throws -> T
  ) throws -> T {
    try withGroup(
      String(localized: description),
      origin: origin,
      body
    )
  }

  /// Synchronous variant of ``withGroup(_:origin:_:)``.
  @_disfavoredOverload
  @discardableResult
  public func withGroup<T>(
    _ description: String,
    origin: UndoGroup.Origin = .local,
    _ body: (Database) throws -> T
  ) throws -> T {
    let barrierID = try beginBarrier(
      description,
      origin: origin
    )
    do {
      let result = try database.write { db in
        try body(db)
      }
      _ = try endBarrier(barrierID)
      return result
    } catch {
      try cancelBarrier(barrierID)
      throw error
    }
  }

  // MARK: - Undo / Redo

  /// Reverts the most-recently-recorded undo group.
  ///
  /// The delegate (if any) is called before the operation is performed so that you can present a
  /// confirmation prompt.
  public func undo() async throws {
    try await perform(.undo)
  }

  /// Reverts changes up to and including a specific undo group.
  ///
  /// The delegate is consulted for each individual step. If a step is cancelled, processing stops.
  public func undo(to group: UndoGroup) async throws {
    try await perform(.undo, to: group)
  }

  /// Re-applies the most-recently-undone group.
  ///
  /// The delegate (if any) is called before the operation is performed so that you can present a
  /// confirmation prompt.
  public func redo() async throws {
    try await perform(.redo)
  }

  /// Re-applies changes up to and including a specific redo group.
  ///
  /// The delegate is consulted for each individual step. If a step is cancelled, processing stops.
  public func redo(to group: UndoGroup) async throws {
    try await perform(.redo, to: group)
  }

  package func writeSyncChanges<T: Sendable>(
    kind: SyncChangeKind = .fetched,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    if kind == .sent {
      return try await $_isUndoRecordingDisabled.withValue(true) {
        try await database.write { db in
          try updates(db)
        }
      }
    }
    switch syncUndoPolicy {
    case .enabled(let actionName):
      return try await recordSyncChanges(actionName: actionName, updates)
    case .disabled(let boundary):
      let result = try await $_isUndoRecordingDisabled.withValue(true) {
        try await database.write { db in
          try updates(db)
        }
      }
      if boundary == .stopAtBoundary {
        dropHistoryAtSyncBoundary()
      }
      return result
    }
  }

  @_disfavoredOverload
  package func writeSyncChanges<T>(
    kind: SyncChangeKind = .fetched,
    _ updates: (Database) throws -> T
  ) throws -> T {
    if kind == .sent {
      return try $_isUndoRecordingDisabled.withValue(true) {
        try database.write { db in
          try updates(db)
        }
      }
    }
    switch syncUndoPolicy {
    case .enabled(let actionName):
      return try recordSyncChanges(actionName: actionName, updates)
    case .disabled(let boundary):
      let result = try $_isUndoRecordingDisabled.withValue(true) {
        try database.write { db in
          try updates(db)
        }
      }
      if boundary == .stopAtBoundary {
        dropHistoryAtSyncBoundary()
      }
      return result
    }
  }

  // MARK: - Freeze / Unfreeze

  /// Suspends undo recording.
  ///
  /// Changes made while recording is frozen are not added to the undo stack.  Call ``unfreeze()``
  /// to resume recording.  Calls to ``freeze()`` and ``unfreeze()`` may be nested.
  public func freeze() async throws {
    try await database.write { _ in
      self._state.withValue { state in
        if state.freezeDepth == 0 {
          state.freezePoint = state.firstLog
        }
        state.freezeDepth += 1
      }
    }
  }

  /// Resumes undo recording after a call to ``freeze()``.
  ///
  /// Any log entries written while frozen are discarded, and ``firstLog`` is advanced past them.
  public func unfreeze() async throws {
    let shouldFinalizeFreeze = _state.withValue { state in
      guard state.freezeDepth > 0 else { return false }
      state.freezeDepth -= 1
      return state.freezeDepth == 0
    }
    guard shouldFinalizeFreeze else { return }

    let maxSeq = try await database.write { db in
      try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq ?? 0
    }
    _state.withValue { state in
      guard state.freezeDepth == 0, state.freezePoint >= 0 else { return }
      state.firstLog = maxSeq + 1
      state.freezePoint = -1
    }
  }

  // MARK: - Private helpers

  private func recordSyncChanges<T: Sendable>(
    actionName: @Sendable (SyncUndoSummary) -> String,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    @Dependency(\.date.now) var now
    let firstLog = _state.value.firstLog
    let result = try await database.write { db in
      try updates(db)
    }
    guard let summary = try await syncUndoSummary(from: firstLog) else {
      return result
    }
    let group = UndoGroup(
      description: actionName(
        SyncUndoSummary(affectedTables: summary.modifiedTables, changeCount: summary.changeCount)
      ),
      origin: .sync,
      date: now
    )
    _ = finalizeBarrier(
      OpenBarrier(group: group, firstLog: firstLog),
      maxSeq: summary.maxSeq,
      modifiedTables: summary.modifiedTables
    )
    return result
  }

  private func recordSyncChanges<T>(
    actionName: @Sendable (SyncUndoSummary) -> String,
    _ updates: (Database) throws -> T
  ) throws -> T {
    @Dependency(\.date.now) var now
    let firstLog = _state.value.firstLog
    let result = try database.write { db in
      try updates(db)
    }
    guard let summary = try syncUndoSummary(from: firstLog) else {
      return result
    }
    let group = UndoGroup(
      description: actionName(
        SyncUndoSummary(affectedTables: summary.modifiedTables, changeCount: summary.changeCount)
      ),
      origin: .sync,
      date: now
    )
    _ = finalizeBarrier(
      OpenBarrier(group: group, firstLog: firstLog),
      maxSeq: summary.maxSeq,
      modifiedTables: summary.modifiedTables
    )
    return result
  }

  private func syncUndoSummary(from firstLog: Int) async throws -> (
    maxSeq: Int, modifiedTables: Set<String>, changeCount: Int
  )? {
    try await database.write { db in
      try syncUndoSummary(in: db, from: firstLog)
    }
  }

  private func syncUndoSummary(from firstLog: Int) throws -> (
    maxSeq: Int, modifiedTables: Set<String>, changeCount: Int
  )? {
    try database.write { db in
      try syncUndoSummary(in: db, from: firstLog)
    }
  }

  private func syncUndoSummary(
    in db: Database,
    from firstLog: Int
  ) throws -> (maxSeq: Int, modifiedTables: Set<String>, changeCount: Int)? {
    guard var maxSeq = try UndoLog.order(by: { $0.seq.desc() }).fetchOne(db)?.seq, maxSeq >= firstLog
    else {
      return nil
    }
    try undoReconcileEntries(in: db, from: firstLog, to: maxSeq)
    maxSeq = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq ?? 0
    guard maxSeq >= firstLog else { return nil }
    let rows = try UndoLog
      .where { $0.seq >= firstLog && $0.seq <= maxSeq }
      .fetchAll(db)
    guard !rows.isEmpty else { return nil }
    return (
      maxSeq,
      Set(rows.map(\.tableName)),
      rows.count
    )
  }

  private func dropHistoryAtSyncBoundary() {
    _$perceptionRegistrar.withMutation(of: self, keyPath: \.undoStack) {
      _$perceptionRegistrar.withMutation(of: self, keyPath: \.redoStack) {
        _state.withValue { state in
          state.undoEntries = []
          state.redoEntries = []
        }
      }
    }
  }

  private func finalizeBarrier(
    _ barrier: OpenBarrier,
    maxSeq: Int,
    modifiedTables: Set<String>
  ) -> UndoGroup? {
    guard maxSeq >= barrier.firstLog else {
      return nil
    }
    let unknownTables = modifiedTables.subtracting(trackedTableNames)
    if !unknownTables.isEmpty {
      reportIssue(
        """
        Undo group '\(barrier.group.description)' recorded changes for unexpected tables: \
        \(unknownTables.sorted().joined(separator: ", ")).
        """
      )
    }
    let entry = UndoEntry(begin: barrier.firstLog, end: maxSeq, group: barrier.group)
    let shouldRecord = _state.withValue { $0.freezePoint < 0 }
    _$perceptionRegistrar.withMutation(of: self, keyPath: \.undoStack) {
      _$perceptionRegistrar.withMutation(of: self, keyPath: \.redoStack) {
        _state.withValue { state in
          if shouldRecord {
            state.undoEntries.append(entry)
            if barrier.group.origin == .local {
              state.redoEntries = []
            } else if barrier.group.origin == .sync && syncRedoPolicy == .clear {
              state.redoEntries = []
            }
            state.firstLog = maxSeq + 1
          }
        }
      }
    }
    if shouldRecord {
      registerFoundationAction(.undo, group: barrier.group)
      return barrier.group
    }
    return nil
  }

  private func perform(_ action: UndoAction) async throws {
    // Peek at the entry to pass to the delegate.
    let entry: UndoEntry? = _state.withValue { state in
      switch action {
      case .undo: return state.undoEntries.last
      case .redo: return state.redoEntries.last
      }
    }
    guard let entry else { return }

    let performAction: @Sendable () async throws -> Void = { [weak self] in
      guard let self else { return }
      try await self.applyInverse(of: entry, action: action)
    }

    if let delegate {
      try await delegate.undoManager(self, willPerform: action, for: entry.group, performAction: performAction)
    } else {
      try await performAction()
    }
  }

  private func perform(_ action: UndoAction, to targetGroup: UndoGroup) async throws {
    let stack: [UndoGroup]
    switch action {
    case .undo:
      stack = undoStack
    case .redo:
      stack = redoStack
    }
    guard let index = stack.firstIndex(where: { $0.id == targetGroup.id }) else { return }
    let count = index + 1
    guard count > 0 else { return }

    for _ in 0..<count {
      let beforeID: UndoGroup.ID?
      switch action {
      case .undo:
        beforeID = undoStack.first?.id
      case .redo:
        beforeID = redoStack.first?.id
      }
      try await perform(action)
      let afterID: UndoGroup.ID?
      switch action {
      case .undo:
        afterID = undoStack.first?.id
      case .redo:
        afterID = redoStack.first?.id
      }
      if beforeID == afterID {
        break
      }
    }
  }

  private func applyInverse(of entry: UndoEntry, action: UndoAction) async throws {
    let firstLog = _state.value.firstLog

    // Execute inverse SQL inside a write transaction.
    // Triggers must run so that inverse-of-inverse statements are recorded for the opposite stack.
    let affectedRows = try await $_isUndoingOrRedoing.withValue(true) {
      try await database.write { db in
        // Fetch inverse SQL rows in reverse order (highest seq first = undo in LIFO order).
        let rows = try UndoLog
          .where { $0.seq >= entry.begin && $0.seq <= entry.end }
          .order { $0.seq.desc() }
          .fetchAll(db)

        let affectedRows = Set(
          rows
            .filter { $0.trackedRowID != 0 }
            .map { UndoAffectedRow(tableName: $0.tableName, rowID: $0.trackedRowID) }
        )

        // Remove these rows from the log before executing so re-entrant calls don't see them.
        try UndoLog
          .where { $0.seq >= entry.begin && $0.seq <= entry.end }
          .delete()
          .execute(db)

        // Replayed statements can include child-before-parent row restoration from cascading
        // deletes. Deferring FK checks until commit lets the full inverse set restore first.
        try #sql("PRAGMA defer_foreign_keys = ON").execute(db)

        // Execute each inverse SQL statement in order.
        for row in rows {
          try #sql("\(raw: row.sql)").execute(db)
        }
        return affectedRows
      }
    }

    // The triggers fired during `applyInverse` will have added new rows to the log.
    let newEnd = try await database.write { db -> Int in
      guard var newEnd = try UndoLog.order(by: { $0.seq.desc() }).fetchOne(db)?.seq else { return 0 }
      if newEnd >= firstLog {
        try undoReconcileEntries(in: db, from: firstLog, to: newEnd)
        newEnd = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq ?? 0
      }
      return newEnd
    }
    let didAppend = newEnd >= firstLog

    let newEntry = UndoEntry(begin: firstLog, end: newEnd, group: entry.group)

    _$perceptionRegistrar.withMutation(of: self, keyPath: \.undoStack) {
      _$perceptionRegistrar.withMutation(of: self, keyPath: \.redoStack) {
        _state.withValue { state in
          switch action {
          case .undo:
            state.undoEntries.removeLast()
            if didAppend {
              state.redoEntries.append(newEntry)
            }
          case .redo:
            state.redoEntries.removeLast()
            if didAppend {
              state.undoEntries.append(newEntry)
            }
          }
          state.firstLog = newEnd + 1
        }
      }
    }

    guard didAppend else { return }
    let eventKind: UndoEvent.Kind
    switch action {
    case .undo: eventKind = .undo
    case .redo: eventKind = .redo
    }
    eventsContinuation.yield(
      UndoEvent(
        kind: eventKind,
        group: entry.group,
        affectedRows: affectedRows
      )
    )
  }

  #if canImport(ObjectiveC)
    private func registerFoundationAction(_ action: UndoAction, group: UndoGroup) {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.registerFoundationActionOnMain(action, group: group)
      }
    }

    @MainActor
    private func registerFoundationActionOnMain(_ action: UndoAction, group: UndoGroup) {
      guard let foundationUndoManager else { return }
      foundationUndoManager.registerUndo(withTarget: self) { target in
        let inverseAction: UndoAction
        switch action {
        case .undo: inverseAction = .redo
        case .redo: inverseAction = .undo
        }
        target.registerFoundationActionOnMain(inverseAction, group: group)
        Task {
          do {
            switch action {
            case .undo:
              try await target.undo()
            case .redo:
              try await target.redo()
            }
          } catch {
            assertionFailure("SQLiteUndoManager failed to perform Foundation undo action: \(error)")
          }
        }
      }
      foundationUndoManager.setActionName(group.description)
    }
  #else
    private func registerFoundationAction(_ action: UndoAction, group: UndoGroup) {}
  #endif
}

#if canImport(SwiftUI)
  @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
  private extension LocalizedStringKey {
    var undoGroupKeyString: String {
      Mirror(reflecting: self)
        .children
        .first { $0.label == "key" }
        .flatMap { $0.value as? String }
        ?? String(describing: self)
    }
  }
#endif

#if canImport(Observation)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension UndoManager: Observable {}
#endif
