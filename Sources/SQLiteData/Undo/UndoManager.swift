import ConcurrencyExtras
import Foundation
import GRDB
import IssueReporting
import Perception
#if canImport(Observation)
  import Observation
#endif
import StructuredQueriesCore

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

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
///   tables: Reminder.self, ReminderTag.self,
///   deviceID: UIDevice.current.identifierForVendor?.uuidString ?? ""
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
  package static let syncDeviceID = "sqlitedata-sync"

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

  private let _state = LockIsolated(State())
  private let database: any DatabaseWriter
  private let databaseID: ObjectIdentifier
  private let deviceID: String
  private let userRecordName: @Sendable () -> String?
  private let trackedTableNames: Set<String>
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

  // MARK: - Init

  /// Creates an undo manager and installs undo triggers on the database.
  ///
  /// The triggers and the temporary log table are created immediately on the writer connection.
  ///
  /// - Parameters:
  ///   - database: The database to observe.
  ///   - tables: The names of the tables whose changes should be undoable.
  ///   - deviceID: An identifier for this device shown in ``UndoGroup/deviceID``.
  ///     Defaults to the system device identifier.
  ///   - userRecordName: A closure returning the current user's iCloud record name, or `nil`.
  ///   - delegate: An optional delegate that can intercept and confirm undo/redo operations.
  public init<
    each T: PrimaryKeyedTable & _SendableMetatype
  >(
    for database: any DatabaseWriter,
    tables: repeat (each T).Type,
    deviceID: String = UndoManager.defaultDeviceID,
    userRecordName: @Sendable @escaping () -> String? = { nil },
    delegate: (any UndoManagerDelegate)? = nil
  ) throws {
    var trackedTableNames = Set<String>()
    for table in repeat each tables {
      trackedTableNames.insert(table.tableName)
    }
    (self.events, self.eventsContinuation) = AsyncStream.makeStream()
    self.database = database
    self.databaseID = ObjectIdentifier(database as AnyObject)
    self.deviceID = deviceID
    self.userRecordName = userRecordName
    self.delegate = delegate
    self.trackedTableNames = trackedTableNames

    // One-time setup on the writer connection: register the custom function,
    // create the temp log table, and install triggers for each observed table.
    try database.write { db in
      db.add(function: $_shouldRecord)
      db.add(function: $_isReplaying)

      try db.execute(sql: undoLogTableSQL)

      for table in repeat each tables {
        let tableName = table.tableName
        let columns = try undoColumnNames(for: tableName, in: db)
        guard !columns.isEmpty else { continue }
        for sql in undoTriggerSQL(for: tableName, columns: columns) {
          try db.execute(sql: sql)
        }
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

  /// A device identifier suitable for use with ``init(for:tables:deviceID:userRecordName:delegate:)``.
  ///
  /// On iOS this is `UIDevice.identifierForVendor`; on macOS it is the machine's host name.
  public static var defaultDeviceID: String {
    #if canImport(UIKit)
      return UIDevice.current.identifierForVendor?.uuidString ?? ProcessInfo.processInfo.hostName
    #else
      return ProcessInfo.processInfo.hostName
    #endif
  }

  /// A SQL expression that reports whether undo/redo replay is currently executing.
  ///
  /// Use this in application trigger `WHEN` clauses to suppress side-effect writes during replay.
  public static func isReplaying() -> some QueryExpression<Bool> {
    $_isReplaying()
  }

  // MARK: - Group recording

  /// Begins recording a barrier that can later be ended or cancelled.
  ///
  /// Use this API when an undoable action spans multiple writes or async boundaries.
  @discardableResult
  public func beginBarrier(
    _ description: String,
    deviceID: String? = nil,
    userRecordName: String? = nil
  ) throws -> UUID {
    let group = UndoGroup(
      description: description,
      deviceID: deviceID ?? self.deviceID,
      userRecordName: userRecordName ?? self.userRecordName(),
      date: Date()
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
      guard var maxSeq = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq,
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
      guard var maxSeq = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq,
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
  @discardableResult
  public func withGroup<T: Sendable>(
    _ description: String,
    deviceID: String? = nil,
    userRecordName: String? = nil,
    _ body: @Sendable (Database) throws -> T
  ) async throws -> T {
    let barrierID = try beginBarrier(
      description,
      deviceID: deviceID,
      userRecordName: userRecordName
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

  /// Synchronous variant of ``withGroup(_:deviceID:userRecordName:_:)``.
  @discardableResult
  public func withGroup<T>(
    _ description: String,
    deviceID: String? = nil,
    userRecordName: String? = nil,
    _ body: (Database) throws -> T
  ) throws -> T {
    let barrierID = try beginBarrier(
      description,
      deviceID: deviceID,
      userRecordName: userRecordName
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

  /// Re-applies the most-recently-undone group.
  ///
  /// The delegate (if any) is called before the operation is performed so that you can present a
  /// confirmation prompt.
  public func redo() async throws {
    try await perform(.redo)
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
            state.redoEntries = []
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
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")

        // Execute each inverse SQL statement in order.
        for row in rows {
          try db.execute(sql: row.sql)
        }
        return affectedRows
      }
    }

    // The triggers fired during `applyInverse` will have added new rows to the log.
    let newEnd = try await database.write { db -> Int in
      guard var newEnd = try UndoLog.order { $0.seq.desc() }.fetchOne(db)?.seq else { return 0 }
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

#if canImport(Observation)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension UndoManager: Observable {}
#endif
