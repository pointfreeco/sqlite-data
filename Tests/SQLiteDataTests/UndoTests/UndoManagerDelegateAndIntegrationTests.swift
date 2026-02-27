import Foundation
import Dependencies
import SQLiteData
import Testing
#if canImport(CloudKit)
  import CloudKit
#endif

@Suite struct UndoManagerDelegateAndIntegrationTests {

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
  #endif
}
