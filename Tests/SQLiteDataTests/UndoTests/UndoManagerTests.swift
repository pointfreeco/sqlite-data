import Foundation
import Dependencies
import SQLiteData
import Testing
#if canImport(CloudKit)
  import CloudKit
#endif

// MARK: - Schema

@Table private struct Item: Equatable, Identifiable {
  let id: Int
  var title: String
}

@Table("notes") private struct Note: Equatable, Identifiable {
  let id: Int
  var body: String?
}

@Table("audits") private struct Audit: Equatable, Identifiable {
  let id: Int
  var message: String
}

@Table("children") private struct Child: Equatable, Identifiable {
  let id: Int
  var parentID: Int
  var name: String
}

// MARK: - Database helpers

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func undoDatabase() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create items") { db in
      try #sql(
        """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL DEFAULT ''
        )
        """
      )
      .execute(db)
    }
    try migrator.migrate(database)
    return database
  }
}

// MARK: - Tests

@Suite struct UndoManagerTests {
  @Test func defaultUndoManagerDependencyDefaultsToNil() {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    #expect(defaultUndoManager == nil)
  }


  // 1. Basic undo removes the inserted row and leaves canUndo false.
  @Test func basicUndo() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "Hello") }.execute(db)
    }
    #expect(undoManager.canUndo)
    #expect(undoManager.undoStack.count == 1)

    try await undoManager.undo()

    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.isEmpty)
    #expect(!undoManager.canUndo)
    #expect(undoManager.undoStack.isEmpty)
  }

  // 2. After undo, redo restores the row and leaves canRedo false.
  @Test func basicRedo() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "Hello") }.execute(db)
    }
    try await undoManager.undo()
    #expect(undoManager.canRedo)

    try await undoManager.redo()

    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
    #expect(items[0].title == "Hello")
    #expect(!undoManager.canRedo)
    #expect(undoManager.redoStack.isEmpty)
  }

  // 3. Two inserts in one withGroup are undone together.
  @Test func undoGroup() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Batch insert") { db in
      _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
      _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
    }
    #expect(undoManager.undoStack.count == 1)

    try await undoManager.undo()

    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.isEmpty)
  }

  // 4. Separate groups produce separate undo entries; undoing removes only the last one.
  @Test func multipleGroups() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Insert A") { db in
      _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
    }
    try await undoManager.withGroup("Insert B") { db in
      _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
    }
    #expect(undoManager.undoStack.count == 2)

    try await undoManager.undo()

    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
    #expect(items[0].title == "A")
    #expect(undoManager.undoStack.count == 1)
  }

  // 5. Sync-origin writes can be grouped, undone, and carry synced-origin metadata.
  @Test func syncIncludedWithOrigin() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await $_isSynchronizingChanges.withValue(true) {
      try await undoManager.withGroup(
        "Sync insert",
        origin: .sync
      ) { db in
        _ = try Item.insert { Item.Draft(title: "Sync item") }.execute(db)
      }
    }

    #expect(undoManager.canUndo)
    #expect(undoManager.undoStack.first?.origin == .sync)

    try await undoManager.undo()
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.isEmpty)
  }

  // 6. Inverse SQL executed during undo is not added to the undo stack; it goes to redo.
  @Test func undoingNotRecorded() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "X") }.execute(db)
    }
    try await undoManager.undo()

    // Only the redo entry should exist; no additional undo entry.
    #expect(undoManager.undoStack.isEmpty)
    #expect(undoManager.redoStack.count == 1)
  }

  // 7. Changes made while frozen are not undoable.
  @Test func freeze() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.freeze()
    // Direct write (not through withGroup) so we can test the trigger suppression via freeze.
    try await db.write { db in
      _ = try Item.insert { Item.Draft(title: "Frozen") }.execute(db)
    }
    try await undoManager.unfreeze()

    #expect(!undoManager.canUndo)
    #expect(undoManager.undoStack.isEmpty)

    // The row should still be in the database.
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
  }

  // 8. When the delegate does not call performAction, the undo is cancelled.
  @Test func explicitBarrierLifecycle() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    let barrierID = try undoManager.beginBarrier("Insert via barrier")
    try await db.write { db in
      _ = try Item.insert { Item.Draft(title: "Barrier item") }.execute(db)
    }
    let group = try await undoManager.endBarrier(barrierID)

    #expect(group?.description == "Insert via barrier")
    #expect(undoManager.undoStack.count == 1)

    try await undoManager.undo()
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.isEmpty)
  }

  @Test func cancelBarrierDropsUndoRegistration() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    let barrierID = try undoManager.beginBarrier("Cancelled barrier")
    try await db.write { db in
      _ = try Item.insert { Item.Draft(title: "Not undoable") }.execute(db)
    }
    try await undoManager.cancelBarrier(barrierID)

    #expect(undoManager.undoStack.isEmpty)
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
  }

  @Test func withoutUndoSuppressesRecording() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await withoutUndo {
      try await undoManager.withGroup("Suppressed insert") { db in
        _ = try Item.insert { Item.Draft(title: "Suppressed") }.execute(db)
      }
    }

    #expect(undoManager.undoStack.isEmpty)
    let items = try await db.read { try Item.fetchAll($0) }
    #expect(items.count == 1)
  }

  @Test func replayFunctionSuppressesAppTriggersDuringUndo() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await db.write { db in
      try db.execute(
        sql: """
          CREATE TABLE "audit_log" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "message" TEXT NOT NULL
          )
          """
      )
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER "item_delete_audit"
          AFTER DELETE ON "items"
          WHEN NOT "sqlitedata_undo_isReplaying"()
          BEGIN
            INSERT INTO "audit_log" ("message") VALUES ('delete ' || OLD."title");
          END
          """
      )
    }

    try await undoManager.withGroup("Insert") { db in
      _ = try Item.insert { Item.Draft(title: "Guarded") }.execute(db)
    }
    try await undoManager.undo()

    let auditCount = try await db.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "audit_log""#) ?? 0
    }
    #expect(auditCount == 0)
  }

  @Test func undoEventEmittedAfterUndo() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)
    var iterator = undoManager.events.makeAsyncIterator()

    try await undoManager.withGroup("Insert event") { db in
      _ = try Item.insert { Item.Draft(title: "Event item") }.execute(db)
    }
    try await undoManager.undo()

    let event = await iterator.next()
    #expect(event?.kind == .undo)
    #expect(event?.group.description == "Insert event")
    #expect(event?.ids(for: Item.self) == [1])
  }

  @Test func noOpGroupIsReconciledAway() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Insert then delete") { db in
      try db.execute(sql: #"INSERT INTO "items" ("title") VALUES ('Temp')"#)
      let id = db.lastInsertedRowID
      try db.execute(sql: #"DELETE FROM "items" WHERE "id" = ?"#, arguments: [id])
    }

    #expect(undoManager.undoStack.isEmpty)
    let count = try await db.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "items""#) ?? 0
    }
    #expect(count == 0)
  }

  @Test func undoDeleteWithCascadeRestoresParentAndChild() async throws {
    let db = try DatabaseQueue()
    try await db.write { db in
      try db.execute(
        sql: """
          CREATE TABLE "parents" (
            "id" INTEGER PRIMARY KEY,
            "name" TEXT NOT NULL DEFAULT ''
          )
          """
      )
      try db.execute(
        sql: """
          CREATE TABLE "children" (
            "id" INTEGER PRIMARY KEY,
            "parentID" INTEGER NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE,
            "name" TEXT NOT NULL DEFAULT ''
          )
          """
      )
    }
    let undoManager = try UndoManager(for: db, tables: Parent.self, Child.self)

    try await withoutUndo {
      try await db.write { db in
        try db.execute(sql: #"INSERT INTO "parents" ("id","name") VALUES (1,'P')"#)
        try db.execute(sql: #"INSERT INTO "children" ("id","parentID","name") VALUES (1,1,'C')"#)
      }
    }

    try await undoManager.withGroup("Delete parent") { db in
      try db.execute(sql: #"DELETE FROM "parents" WHERE "id" = 1"#)
    }

    let deletedCounts = try await db.read { db in
      (
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "parents""#) ?? 0,
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "children""#) ?? 0
      )
    }
    #expect(deletedCounts.0 == 0)
    #expect(deletedCounts.1 == 0)

    try await undoManager.undo()

    let restoredCounts = try await db.read { db in
      (
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "parents""#) ?? 0,
        try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "children""#) ?? 0
      )
    }
    #expect(restoredCounts.0 == 1)
    #expect(restoredCounts.1 == 1)
  }

  @Test func warnsOnUnexpectedTrackedTableNames() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await db.write { db in
      try db.execute(
        sql: """
          CREATE TABLE "audits" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "message" TEXT NOT NULL DEFAULT ''
          )
          """
      )
      try Audit.installUndoTriggers(in: db)
    }

    try await withKnownIssue {
      try await undoManager.withGroup("Mixed tracked tables") { db in
        _ = try Item.insert { Item.Draft(title: "Item") }.execute(db)
        _ = try Audit.insert { Audit.Draft(message: "Audit") }.execute(db)
      }
    } matching: { issue in
      issue.description.contains("unexpected tables: audits")
    }
  }

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

  // 11. The description from withGroup appears in undoStack.
  @Test func undoDescriptionRoundtrip() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.withGroup("Delete all items") { db in
      _ = try Item.insert { Item.Draft(title: "Temp") }.execute(db)
    }

    #expect(undoManager.undoStack.first?.description == "Delete all items")
  }

  // 12. Nested freeze calls require matching unfreeze calls before recording resumes.
  @Test func nestedFreezeRequiresMatchingUnfreeze() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let undoManager = try UndoManager(for: db, tables: Item.self)

    try await undoManager.freeze()
    try await undoManager.freeze()

    try await undoManager.withGroup("Frozen A") { db in
      _ = try Item.insert { Item.Draft(title: "A") }.execute(db)
    }
    try await undoManager.unfreeze()

    try await undoManager.withGroup("Frozen B") { db in
      _ = try Item.insert { Item.Draft(title: "B") }.execute(db)
    }

    #expect(!undoManager.canUndo)

    try await undoManager.unfreeze()

    try await undoManager.withGroup("Tracked C") { db in
      _ = try Item.insert { Item.Draft(title: "C") }.execute(db)
    }
    #expect(undoManager.undoStack.count == 1)

    try await undoManager.undo()

    let titles = try await db.read { db in
      try String.fetchAll(db, sql: "SELECT title FROM items ORDER BY id")
    }
    #expect(titles == ["A", "B"])
  }

  // 13. Undo/redo round-trips updates containing SQL-sensitive quoting characters.
  @Test func updateUndoRedoQuotedText() async throws {
    let db = try DatabaseQueue.undoDatabase()
    let id = try await db.write { db in
      try db.execute(sql: #"INSERT INTO "items" ("title") VALUES (?)"#, arguments: ["Before"])
      return db.lastInsertedRowID
    }
    let undoManager = try UndoManager(for: db, tables: Item.self)
    let updatedTitle = #"O'Reilly "Book""#

    try await undoManager.withGroup("Quoted update") { db in
      try db.execute(
        sql: #"UPDATE "items" SET "title" = ? WHERE "id" = ?"#,
        arguments: [updatedTitle, id]
      )
    }

    let titleAfterUpdate = try await db.read { db in
      try String.fetchOne(db, sql: #"SELECT "title" FROM "items" WHERE "id" = ?"#, arguments: [id])
    }
    #expect(titleAfterUpdate == updatedTitle)

    try await undoManager.undo()
    let titleAfterUndo = try await db.read { db in
      try String.fetchOne(db, sql: #"SELECT "title" FROM "items" WHERE "id" = ?"#, arguments: [id])
    }
    #expect(titleAfterUndo == "Before")

    try await undoManager.redo()
    let titleAfterRedo = try await db.read { db in
      try String.fetchOne(db, sql: #"SELECT "title" FROM "items" WHERE "id" = ?"#, arguments: [id])
    }
    #expect(titleAfterRedo == updatedTitle)
  }

  // 14. Deleting rows with NULL values can be undone/redone correctly.
  @Test func deleteUndoRedoNullColumn() async throws {
    let db = try DatabaseQueue()
    try await db.write { db in
      try db.execute(sql: #"CREATE TABLE "notes" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "body" TEXT)"#)
    }
    let id = try await db.write { db in
      try db.execute(sql: #"INSERT INTO "notes" ("body") VALUES (NULL)"#)
      return db.lastInsertedRowID
    }
    let undoManager = try UndoManager(for: db, tables: Note.self)

    try await undoManager.withGroup("Delete null row") { db in
      try db.execute(sql: #"DELETE FROM "notes" WHERE "id" = ?"#, arguments: [id])
    }

    let countAfterDelete = try await db.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "notes" WHERE "id" = ?"#, arguments: [id]) ?? 0
    }
    #expect(countAfterDelete == 0)

    try await undoManager.undo()
    let countAfterUndo = try await db.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "notes" WHERE "id" = ?"#, arguments: [id]) ?? 0
    }
    let restoredIsNull = try await db.read { db in
      try Int.fetchOne(
        db,
        sql: #"SELECT "body" IS NULL FROM "notes" WHERE "id" = ?"#,
        arguments: [id]
      ) ?? 0
    }
    #expect(countAfterUndo == 1)
    #expect(restoredIsNull == 1)

    try await undoManager.redo()
    let countAfterRedo = try await db.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "notes" WHERE "id" = ?"#, arguments: [id]) ?? 0
    }
    #expect(countAfterRedo == 0)
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
