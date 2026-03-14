import Foundation
import Dependencies
import DependenciesTestSupport
import SQLiteData
import Testing
#if canImport(CloudKit)
  import CloudKit
#endif

@Suite(.dependencies { $0.date.now = Date(timeIntervalSince1970: 0) })
struct UndoManagerDelegateAndIntegrationTests {

  @Test func delegateCancel() async throws {
    final class CancelDelegate: UndoManagerDelegate {
      func undoManager(
        _ undoManager: SQLiteData.UndoManager,
        willPerform action: UndoAction,
        for group: UndoGroup,
        performAction: @Sendable () async throws -> Void
      ) async throws {
        // Intentionally do NOT call performAction — cancel the undo.
      }
    }

    let db = try DatabaseQueue.undoDatabase()
    let delegate = CancelDelegate()
    let undoManager = try UndoManager(for: db, tables: Item.self, delegate: delegate)

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "Persistent") }.execute(db)
    }
    #expect(undoManager.undoStack.count == 1)

    try await undoManager.undo()

    // Stack unchanged; row still present.
    #expect(undoManager.undoStack.count == 1)
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
  }

  // 9. The delegate receives metadata matching what was passed to withGroup.
  @Test func delegateReceivesMetadata() async throws {
    actor MetadataCapture {
      var capturedGroup: UndoGroup?
      func capture(_ group: UndoGroup) { capturedGroup = group }
    }
    let capture = MetadataCapture()

    final class MetadataDelegate: UndoManagerDelegate, @unchecked Sendable {
      let capture: MetadataCapture
      init(_ capture: MetadataCapture) { self.capture = capture }
      func undoManager(
        _ undoManager: SQLiteData.UndoManager,
        willPerform action: UndoAction,
        for group: UndoGroup,
        performAction: @Sendable () async throws -> Void
      ) async throws {
        await capture.capture(group)
        try await performAction()
      }
    }

    let db = try DatabaseQueue.undoDatabase()
    let delegate = MetadataDelegate(capture)
    let undoManager = try UndoManager(
      for: db,
      tables: Item.self,
      delegate: delegate
    )

    try await undoManager.withGroup("My operation") { db in
      _ = try Item.insert { Item.Draft(title: "Hi") }.execute(db)
    }
    try await undoManager.undo()

    let group = await capture.capturedGroup
    #expect(group?.description == "My operation")
    #expect(group?.origin == .local)
  }

  // 10. The delegate receives `.undo` for undo and `.redo` for redo.
  @Test func delegateActionType() async throws {
    actor ActionCapture {
      var actions: [UndoAction] = []
      func append(_ action: UndoAction) { actions.append(action) }
    }
    let capture = ActionCapture()

    final class ActionDelegate: UndoManagerDelegate, @unchecked Sendable {
      let capture: ActionCapture
      init(_ capture: ActionCapture) { self.capture = capture }
      func undoManager(
        _ undoManager: SQLiteData.UndoManager,
        willPerform action: UndoAction,
        for group: UndoGroup,
        performAction: @Sendable () async throws -> Void
      ) async throws {
        await capture.append(action)
        try await performAction()
      }
    }

    let db = try DatabaseQueue.undoDatabase()
    let delegate = ActionDelegate(capture)
    let undoManager = try UndoManager(for: db, tables: Item.self, delegate: delegate)

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "Z") }.execute(db)
    }
    try await undoManager.undo()
    try await undoManager.redo()

    let actions = await capture.actions
    #expect(actions == [.undo, .redo])
  }

  @Test func undoToStopsWhenDelegateCancelsMidJump() async throws {
    actor CallCounter {
      var count = 0
      func increment() -> Int {
        count += 1
        return count
      }
      func value() -> Int { count }
    }
    let counter = CallCounter()

    final class CancelOnSecondCallDelegate: UndoManagerDelegate, @unchecked Sendable {
      let counter: CallCounter
      init(counter: CallCounter) {
        self.counter = counter
      }

      func undoManager(
        _ undoManager: SQLiteData.UndoManager,
        willPerform action: UndoAction,
        for group: UndoGroup,
        performAction: @Sendable () async throws -> Void
      ) async throws {
        let call = await counter.increment()
        if call == 1 {
          try await performAction()
        }
      }
    }

    let db = try DatabaseQueue.undoDatabase()
    let delegate = CancelOnSecondCallDelegate(counter: counter)
    let undoManager = try UndoManager(for: db, tables: Item.self, delegate: delegate)

    try await undoManager.withGroup("Insert A") { db in
      _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
    }
    try await undoManager.withGroup("Insert B") { db in
      _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
    }
    try await undoManager.withGroup("Insert C") { db in
      _ = try Item.insert { Item.Draft(title: "C") }.execute(db)
    }

    let target = try #require(undoManager.undoStack.dropFirst().first)
    try await undoManager.undo(to: target)

    let titles = try await db.read { db in
      try String.fetchAll(db, sql: "SELECT title FROM items ORDER BY id")
    }
    #expect(titles == ["A", "B"])
    #expect(await counter.value() == 2)
  }

  #if canImport(ObjectiveC)
    @Test func foundationUndoBridgeRoundTrip() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let sqliteUndoManager = try SQLiteUndoManager(for: db, tables: Item.self)
      let foundationUndoManager = await MainActor.run { Foundation.UndoManager() }
      sqliteUndoManager.bind(to: foundationUndoManager)

      try await sqliteUndoManager.withGroup("Insert via bridge") { db in
        _ = try Item.insert { Item.Draft(title: "Hello") }.execute(db)
      }

      try await waitUntil {
        await MainActor.run { foundationUndoManager.canUndo }
      }
      #expect(await MainActor.run { foundationUndoManager.canUndo })

      await MainActor.run { foundationUndoManager.undo() }

      try await waitUntil {
        let count = try await db.read { db in
          try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "items""#) ?? 0
        }
        return count == 0 && sqliteUndoManager.canRedo
      }

      let countAfterUndo = try await db.read { db in
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "items""#) ?? 0
      }
      #expect(countAfterUndo == 0)
      #expect(sqliteUndoManager.canRedo)
      #expect(await MainActor.run { foundationUndoManager.canRedo })

      await MainActor.run { foundationUndoManager.redo() }

      try await waitUntil {
        let count = try await db.read { db in
          try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "items""#) ?? 0
        }
        return count == 1 && sqliteUndoManager.canUndo
      }

      let countAfterRedo = try await db.read { db in
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "items""#) ?? 0
      }
      #expect(countAfterRedo == 1)
      #expect(sqliteUndoManager.canUndo)
    }

    @Test func foundationUndoBridgeUnboundFallback() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let sqliteUndoManager = try SQLiteUndoManager(for: db, tables: Item.self)
      let foundationUndoManager = await MainActor.run { Foundation.UndoManager() }

      try await sqliteUndoManager.withGroup("Standalone insert") { db in
        _ = try Item.insert { Item.Draft(title: "Hello") }.execute(db)
      }

      try await Task.sleep(nanoseconds: 50_000_000)

      #expect(sqliteUndoManager.canUndo)
      #expect(!(await MainActor.run { foundationUndoManager.canUndo }))
    }

    private func waitUntil(
      _ condition: @escaping @Sendable () async throws -> Bool
    ) async throws {
      for _ in 0..<200 {
        if try await condition() {
          return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      #expect(Bool(false))
    }
  #endif

  #if canImport(CloudKit)
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncEngineWriteWrappedByUserDatabaseIsUndoable() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Synced item") }.execute(db)
        }
      }

      #expect(undoManager.undoStack.count == 1)
      #expect(undoManager.undoStack.first?.origin == .sync)

      try await undoManager.undo()
      let items = try await db.read { try Item.fetchAll($0) }
      #expect(items.isEmpty)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncEngineWriteWithoutUndoManagerStillWorks() async throws {
      try await withDependencies {
        $0.defaultUndoManager = nil
      } operation: {
        let db = try DatabaseQueue.undoDatabase()
        let userDatabase = UserDatabase(database: db)
        let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Synced item") }.execute(db)
          }
        }

        let items = try await db.read { try Item.fetchAll($0) }
        #expect(items.count == 1)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncUndoPolicyCustomActionName() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncUndoPolicy: .enabled(
          actionName: { summary in
            "Synced \(summary.changeCount) changes across \(summary.affectedTables.count) table(s)"
          }
        )
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Synced item") }.execute(db)
        }
      }

      #expect(undoManager.undoStack.count == 1)
      #expect(undoManager.undoStack.first?.origin == .sync)
      #expect(undoManager.undoStack.first?.description == "Synced 1 changes across 1 table(s)")
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncWriteDoesNotClearRedoStack() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      // 1. Make a local change
      try await undoManager.withGroup("Add item") { db in
        _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
      }
      #expect(undoManager.undoStack.count == 1)

      // 2. Undo the local change — it moves to redo stack
      try await undoManager.undo()
      #expect(undoManager.undoStack.isEmpty)
      #expect(undoManager.redoStack.count == 1)
      #expect(undoManager.redoStack.first?.description == "Add item")

      // 3. A sync write arrives — should NOT clear the redo stack
      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Synced") }.execute(db)
        }
      }
      #expect(undoManager.undoStack.count == 1)
      #expect(undoManager.undoStack.first?.origin == .sync)
      #expect(undoManager.redoStack.count == 1, "Sync write should not clear redo stack")
      #expect(undoManager.redoStack.first?.description == "Add item")

      // 4. Redo the local change — it should still work
      try await undoManager.redo()
      let titles = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT title FROM items ORDER BY id")
      }
      #expect(titles.contains("Local"))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncUndoPolicyDisabledAllowCrossing() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncUndoPolicy: .disabled(boundary: .allowCrossing)
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await undoManager.withGroup("Local A") { db in
        _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
      }
      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Sync") }.execute(db)
        }
      }
      try await undoManager.withGroup("Local B") { db in
        _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
      }

      #expect(undoManager.undoStack.map(\.description) == ["Local B", "Local A"])
      #expect(undoManager.undoStack.allSatisfy { $0.origin == .local })

      try await undoManager.undo()
      try await undoManager.undo()

      let titles = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT title FROM items ORDER BY id")
      }
      #expect(titles == ["Sync"])
      #expect(undoManager.undoStack.isEmpty)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncUndoPolicyDisabledStopAtBoundary() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncUndoPolicy: .disabled(boundary: .stopAtBoundary)
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await undoManager.withGroup("Local A") { db in
        _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
      }
      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Sync") }.execute(db)
        }
      }
      try await undoManager.withGroup("Local B") { db in
        _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
      }

      #expect(undoManager.undoStack.map(\.description) == ["Local B"])

      try await undoManager.undo()
      try await undoManager.undo()

      let titles = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT title FROM items ORDER BY id")
      }
      #expect(titles == ["A", "Sync"])
      #expect(undoManager.undoStack.isEmpty)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sentSyncWriteDoesNotCreateUndoGroup() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await $_syncChangeKind.withValue(.sent) {
        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Echo") }.execute(db)
          }
        }
      }

      #expect(undoManager.undoStack.isEmpty)
      let items = try await db.read { try Item.fetchAll($0) }
      #expect(items.count == 1)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func fetchedSyncWriteCreatesUndoGroup() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await $_syncChangeKind.withValue(.fetched) {
        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Remote") }.execute(db)
          }
        }
      }

      #expect(undoManager.undoStack.count == 1)
      #expect(undoManager.undoStack.first?.origin == .sync)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sentSyncWritePreservesRedoStack() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await undoManager.withGroup("Add item") { db in
        _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
      }
      try await undoManager.undo()
      #expect(undoManager.redoStack.count == 1)

      try await $_syncChangeKind.withValue(.sent) {
        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Echo") }.execute(db)
          }
        }
      }

      #expect(undoManager.redoStack.count == 1, "Sent sync write should not clear redo stack")
      #expect(undoManager.undoStack.isEmpty, "Sent sync write should not create undo group")
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncRedoPolicyClearClearsRedoOnFetchedSync() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncRedoPolicy: .clear
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await undoManager.withGroup("Add item") { db in
        _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
      }
      try await undoManager.undo()
      #expect(undoManager.redoStack.count == 1)

      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Remote") }.execute(db)
        }
      }

      #expect(undoManager.redoStack.isEmpty, "syncRedoPolicy .clear should clear redo stack")
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func syncRedoPolicyPreserveKeepsRedoOnFetchedSync() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncRedoPolicy: .preserve
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await undoManager.withGroup("Add item") { db in
        _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
      }
      try await undoManager.undo()
      #expect(undoManager.redoStack.count == 1)

      try await $_currentZoneID.withValue(zoneID) {
        try await userDatabase.write { db in
          _ = try Item.insert { Item.Draft(title: "Remote") }.execute(db)
        }
      }

      #expect(undoManager.undoStack.count == 1)
      #expect(undoManager.redoStack.count == 1, "syncRedoPolicy .preserve should keep redo stack")
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func hasSyncChangesSinceReturnsTrueAfterFetchedSync() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncRedoPolicy: .preserve
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 100)
      } operation: {
        try await undoManager.withGroup("Add item") { db in
          _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
        }
      }
      try await undoManager.undo()
      let redoGroup = try #require(undoManager.redoStack.first)

      try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 200)
      } operation: {
        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Remote") }.execute(db)
          }
        }
      }

      #expect(undoManager.hasSyncChangesSince(redoGroup))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func hasSyncChangesSinceReturnsFalseWhenNoSync() async throws {
      let db = try DatabaseQueue.undoDatabase()
      let undoManager = try UndoManager(for: db, tables: Item.self)

      try await undoManager.withGroup("Add item") { db in
        _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
      }
      try await undoManager.undo()
      let redoGroup = try #require(undoManager.redoStack.first)

      #expect(!undoManager.hasSyncChangesSince(redoGroup))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func delegateCanConfirmRedoAfterSyncChanges() async throws {
      actor RedoCapture {
        var confirmedRedo = false
        func confirm() { confirmedRedo = true }
        func value() -> Bool { confirmedRedo }
      }
      let capture = RedoCapture()

      final class ConfirmRedoDelegate: UndoManagerDelegate, @unchecked Sendable {
        let capture: RedoCapture
        init(capture: RedoCapture) {
          self.capture = capture
        }
        func undoManager(
          _ undoManager: SQLiteData.UndoManager,
          willPerform action: UndoAction,
          for group: UndoGroup,
          performAction: @Sendable () async throws -> Void
        ) async throws {
          if action == .redo, undoManager.hasSyncChangesSince(group) {
            await capture.confirm()
          }
          try await performAction()
        }
      }

      let db = try DatabaseQueue.undoDatabase()
      let delegate = ConfirmRedoDelegate(capture: capture)
      let undoManager = try UndoManager(
        for: db,
        tables: Item.self,
        syncRedoPolicy: .preserve,
        delegate: delegate
      )
      let userDatabase = UserDatabase(database: db)
      let zoneID = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "collaborator-user")

      try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 100)
      } operation: {
        try await undoManager.withGroup("Add item") { db in
          _ = try Item.insert { Item.Draft(title: "Local") }.execute(db)
        }
      }
      try await undoManager.undo()

      try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 200)
      } operation: {
        try await $_currentZoneID.withValue(zoneID) {
          try await userDatabase.write { db in
            _ = try Item.insert { Item.Draft(title: "Remote") }.execute(db)
          }
        }
      }

      try await undoManager.redo()
      #expect(await capture.value(), "Delegate should detect sync changes since redo group")
    }
  #endif
}
