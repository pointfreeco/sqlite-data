import Foundation
import GRDB
import StructuredQueriesCore

// MARK: - Undo log table

/// The DDL that creates the per-connection temporary undo log table.
package let undoLogTableSQL = """
  CREATE TEMP TABLE IF NOT EXISTS "sqlitedata_undo_log" (
    "seq" INTEGER PRIMARY KEY AUTOINCREMENT,
    "tableName" TEXT NOT NULL,
    "trackedRowID" INTEGER NOT NULL DEFAULT 0,
    "sql" TEXT NOT NULL
  )
  """

// MARK: - Trigger installation

extension PrimaryKeyedTable {
  package static func installUndoTriggers(in db: Database) throws {
    guard !undoWritableColumnNames.isEmpty else { return }
    try undoInsertTrigger.execute(db)
    try undoUpdateTrigger.execute(db)
    try undoDeleteTrigger.execute(db)
  }

  fileprivate static var undoInsertTrigger: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "_sqlitedata_undo_insert_\(tableName)",
      ifNotExists: true,
      after: .insert { new in
        UndoLog.insert {
          ($0.tableName, $0.trackedRowID, $0.sql)
        } select: {
          Values(
            tableName,
            new.rowid,
            #sql(
              "'DELETE FROM \(raw: undoQuotedTableName) WHERE rowid=' || \(new.rowid)",
              as: String.self
            )
          )
        }
      } when: { _ in
        $_shouldRecord()
      }
    )
  }

  fileprivate static var undoUpdateTrigger: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "_sqlitedata_undo_update_\(tableName)",
      ifNotExists: true,
      before: .update { old, _ in
        UndoLog.insert {
          ($0.tableName, $0.trackedRowID, $0.sql)
        } select: {
          Values(
            tableName,
            old.rowid,
            #sql(
              "'UPDATE \(raw: undoQuotedTableName) SET \(raw: undoSetClause) WHERE rowid=' || \(old.rowid)",
              as: String.self
            )
          )
        }
      } when: { _, _ in
        $_shouldRecord() && #sql("\(raw: undoChangedCondition)", as: Bool.self)
      }
    )
  }

  fileprivate static var undoDeleteTrigger: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "_sqlitedata_undo_delete_\(tableName)",
      ifNotExists: true,
      before: .delete { old in
        UndoLog.insert {
          ($0.tableName, $0.trackedRowID, $0.sql)
        } select: {
          Values(
            tableName,
            old.rowid,
            #sql(
              "'INSERT INTO \(raw: undoQuotedTableName)(rowid,\(raw: undoColumnList)) VALUES(' || \(old.rowid) || ',\(raw: undoValueList))'",
              as: String.self
            )
          )
        }
      } when: { _ in
        $_shouldRecord()
      }
    )
  }

  fileprivate static var undoWritableColumnNames: [String] {
    Self.TableColumns.writableColumns.map(\.name)
  }

  fileprivate static var undoQuotedTableName: String {
    undoDoubleQuotedIdentifier(tableName)
  }

  fileprivate static var undoChangedCondition: String {
    undoWritableColumnNames
      .map { column in
        let columnIdentifier = undoDoubleQuotedIdentifier(column)
        return "OLD.\(columnIdentifier) IS NOT NEW.\(columnIdentifier)"
      }
      .joined(separator: " OR ")
  }

  fileprivate static var undoSetClause: String {
    undoWritableColumnNames
      .map { column in
        let columnIdentifier = undoDoubleQuotedIdentifier(column)
        return "\(columnIdentifier)='||quote(OLD.\(columnIdentifier))||'"
      }
      .joined(separator: ",")
  }

  fileprivate static var undoColumnList: String {
    undoWritableColumnNames
      .map(undoDoubleQuotedIdentifier)
      .joined(separator: ",")
  }

  fileprivate static var undoValueList: String {
    undoWritableColumnNames
      .map { column in
        "'||quote(OLD.\(undoDoubleQuotedIdentifier(column)))||'"
      }
      .joined(separator: ",")
  }
}

// MARK: - Undo log analysis

package func undoModifiedTableNames(in db: Database, from startSeq: Int, to endSeq: Int) throws -> Set<String> {
  Set(
    try UndoLog
      .where { $0.seq >= startSeq && $0.seq <= endSeq }
      .select(\.tableName)
      .fetchAll(db)
  )
}

package func undoReconcileEntries(in db: Database, from startSeq: Int, to endSeq: Int) throws {
  let entries = try UndoLog
    .where { $0.seq >= startSeq && $0.seq <= endSeq }
    .order { $0.seq.asc() }
    .fetchAll(db)

  var grouped = [String: [UndoLog]]()
  for entry in entries where entry.trackedRowID != 0 {
    grouped["\(entry.tableName):\(entry.trackedRowID)", default: []].append(entry)
  }

  var seqsToDelete: [Int] = []
  for (_, group) in grouped where group.count > 1 {
    let first = group[0]
    let last = group[group.count - 1]

    let firstIsDeleteReverse = first.sql.uppercased().hasPrefix("DELETE FROM")
    let lastIsInsertReverse = last.sql.uppercased().hasPrefix("INSERT INTO")

    if firstIsDeleteReverse && lastIsInsertReverse {
      seqsToDelete.append(contentsOf: group.map(\.seq))
      continue
    }

    if firstIsDeleteReverse {
      seqsToDelete.append(contentsOf: group.dropFirst().map(\.seq))
      continue
    }

    seqsToDelete.append(
      contentsOf: group.dropFirst().compactMap {
        $0.sql.uppercased().hasPrefix("UPDATE") ? $0.seq : nil
      }
    )
  }

  guard !seqsToDelete.isEmpty else { return }
  try UndoLog
    .where { $0.seq.in(seqsToDelete) }
    .delete()
    .execute(db)
}

// MARK: - Helpers

private func undoDoubleQuotedIdentifier(_ identifier: String) -> String {
  "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
