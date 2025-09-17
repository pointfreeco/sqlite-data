import CustomDump
import Dependencies
import Foundation
import GRDB
import InlineSnapshotTesting
import StructuredQueriesCore
import StructuredQueriesGRDBCore
import StructuredQueriesTestSupport

/// An end-to-end snapshot testing helper for database content.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - includeSQL: Whether to snapshot the SQL fragment in addition to the results.
///   - query: A statement.
///   - database: The database to use. A value of `nil` will use
///     `@Dependency(\.defaultDatabase)`.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@_disfavoredOverload
public func assertQuery<each V: QueryRepresentable, S: StructuredQueriesCore.Statement<(repeat each V)>>(
  includeSQL: Bool = false,
  _ query: S,
  database: (any DatabaseWriter)? = nil,
  sql sqlSnapshot: (() -> String)? = nil,
  results resultsSnapshot: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  if includeSQL {
    assertInlineSnapshot(
      of: query,
      as: .sql,
      message: "Query did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "sql",
        trailingClosureOffset: 0
      ),
      matches: sqlSnapshot,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
  let results = includeSQL ? resultsSnapshot : sqlSnapshot
  do {
    @Dependency(\.defaultDatabase) var defaultDatabase
    let rows = try (database ?? defaultDatabase).write { try query.fetchAll($0) }
    var table = ""
    if rows.isEmpty {
      table = "(No results)"
    } else {
      printTable(rows, to: &table)
    }
    if !table.isEmpty {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? 1 : 0
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    } else if results != nil {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results expected to be empty",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? 1 : 0
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }
  } catch {
    assertInlineSnapshot(
      of: error.localizedDescription,
      as: .lines,
      message: "Results did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "results",
        trailingClosureOffset: includeSQL ? 1 : 0
      ),
      matches: results,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
}

/// An end-to-end snapshot testing helper for database content.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - includeSQL: Whether to snapshot the SQL fragment in addition to the results.
///   - query: A statement.
///   - sql: A snapshot of the SQL produced by the statement.
///   - database: The database to use. A value of `nil` will use
///     `@Dependency(\.defaultDatabase)`.
///   - results: A snapshot of the results.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public func assertQuery<S: SelectStatement, each J: StructuredQueriesCore.Table>(
  includeSQL: Bool = false,
  _ query: S,
  database: (any DatabaseWriter)? = nil,
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) where S.QueryValue == (), S.Joins == (repeat each J) {
  assertQuery(
    includeSQL: includeSQL,
    query.selectStar(),
    database: database,
    sql: sql,
    results: results,
    fileID: fileID,
    filePath: filePath,
    function: function,
    line: line,
    column: column
  )
}

private func printTable<each C>(_ rows: [(repeat each C)], to output: inout some TextOutputStream) {
  var maxColumnSpan: [Int] = []
  var hasMultiLineRows = false
  for _ in repeat (each C).self {
    maxColumnSpan.append(0)
  }
  var table: [([[Substring]], maxRowSpan: Int)] = []
  for row in rows {
    var columns: [[Substring]] = []
    var index = 0
    var maxRowSpan = 0
    for column in repeat each row {
      defer { index += 1 }
      var cell = ""
      customDump(column, to: &cell)
      let lines = cell.split(separator: "\n")
      hasMultiLineRows = hasMultiLineRows || lines.count > 1
      maxRowSpan = max(maxRowSpan, lines.count)
      maxColumnSpan[index] = max(maxColumnSpan[index], lines.map(\.count).max() ?? 0)
      columns.append(lines)
    }
    table.append((columns, maxRowSpan))
  }
  guard !table.isEmpty else { return }
  output.write("┌─")
  output.write(
    maxColumnSpan
      .map { String(repeating: "─", count: $0) }
      .joined(separator: "─┬─")
  )
  output.write("─┐\n")
  for (offset, rowAndMaxRowSpan) in table.enumerated() {
    let (row, maxRowSpan) = rowAndMaxRowSpan
    for rowOffset in 0..<maxRowSpan {
      output.write("│ ")
      var line: [String] = []
      for (columns, maxColumnSpan) in zip(row, maxColumnSpan) {
        if columns.count <= rowOffset {
          line.append(String(repeating: " ", count: maxColumnSpan))
        } else {
          line.append(
            columns[rowOffset]
              + String(repeating: " ", count: maxColumnSpan - columns[rowOffset].count)
          )
        }
      }
      output.write(line.joined(separator: " │ "))
      output.write(" │\n")
    }
    if hasMultiLineRows, offset != table.count - 1 {
      output.write("├─")
      output.write(
        maxColumnSpan
          .map { String(repeating: "─", count: $0) }
          .joined(separator: "─┼─")
      )
      output.write("─┤\n")
    }
  }
  output.write("└─")
  output.write(
    maxColumnSpan
      .map { String(repeating: "─", count: $0) }
      .joined(separator: "─┴─")
  )
  output.write("─┘")
}
